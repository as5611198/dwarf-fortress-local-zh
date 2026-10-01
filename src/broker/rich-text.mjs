import { mentionsTerm, validateTranslation } from './safety.mjs';

const kinds = ['figure', 'site', 'artifact', 'book', 'region', 'layer',
  'entity', 'building', 'population', 'art', 'era', 'collection'];
const linkToken = /\{\{DFL\d+\}\}/g;
const renderedAlias = /^(?:L[A-Za-z0-9]{3}_+|L[A-Za-z0-9]{6}_+|L(?=[A-Za-z0-9]{0,5}\d)[A-Za-z0-9]{6})$/;

export function validateParagraphRequest(request) {
  if (request.kind !== 'legends-paragraph' || !Array.isArray(request.links) ||
      request.links.length > 64 || (request.subjectId !== undefined &&
      (!Number.isSafeInteger(request.subjectId) || request.subjectId < 0))) {
    throw new Error('invalid paragraph links');
  }
  const tokens = [...request.text.matchAll(/\{\{DFL(\d+)\}\}/g)].map(match => Number(match[1]));
  if (tokens.length !== request.links.length || new Set(tokens).size !== tokens.length ||
      tokens.some(index => index >= request.links.length) || request.links.some(link =>
        !Number.isSafeInteger(link.type) || link.type < 0 || link.type >= kinds.length ||
        !Number.isSafeInteger(link.id) || link.id < 0 || typeof link.text !== 'string' ||
        !link.text.trim() || link.text.length > 2000)) throw new Error('invalid paragraph links');
}

export function validateParagraph(request, result) {
  validateParagraphRequest(request);
  if (!result || !Array.isArray(result.links) || result.links.length !== request.links.length) {
    throw new Error('invalid paragraph links');
  }
  return {translation: validateTranslation(request.text, result.translation),
    links: result.links.map((link, index) => ({
      translation: validateTranslation(renderedAlias.test(request.links[index].text) ?
        '連結' : request.links[index].text, link.translation),
    }))};
}

function linkOnlyTranslation(source) {
  const remainder = source.replace(linkToken, '');
  return /^[\s\p{P}\p{S}\p{N}]*$/u.test(remainder) ? source : null;
}

async function entityCanonical(entity, names, broker) {
  return names.canonical(entity,broker);
}

async function entityGlossary(entity, names, broker) {
  const canonical = await entityCanonical(entity, names, broker);
  return Object.fromEntries([...entity.aliases, ...(entity.shortAliases ?? [])]
    .map(alias => [alias, canonical]));
}

export async function translateParagraph(request, names, broker) {
  validateParagraphRequest(request);
  await names.refresh(broker);
  if (request.world !== names.world) throw new Error('Legends paragraph world mismatch');
  const generation = names.generation;
  const subject = request.subjectId === undefined ? null : names.byId.get(`figure:${request.subjectId}`);
  if (request.subjectId !== undefined && !subject) throw new Error('Legends subject identity mismatch');
  const glossary = subject ? await entityGlossary(subject, names, broker) : {};
  const links = [];
  for (const link of request.links) {
    const entity = names.byId.get(`${kinds[link.type]}:${link.id}`);
    let scoped = {};
    if (entity) {
      const aliases = [...entity.aliases, ...(entity.shortAliases ?? [])];
      if (!renderedAlias.test(link.text) && !aliases.some(alias => mentionsTerm(link.text, alias))) {
        throw new Error('Legends link identity mismatch');
      }
      scoped = await entityGlossary(entity, names, broker);
    } else if (link.type === 0) throw new Error('Legends link identity mismatch');
    const translation = renderedAlias.test(link.text) ?
      (entity ? await entityCanonical(entity, names, broker) :
        await broker.canonicalLink(names.world, `${kinds[link.type]}:${link.id}`, link.text,
          () => { throw new Error('Legends rendered link identity mismatch'); })) :
      entity ? await broker.translate(link.text, {glossary: scoped}) :
        await broker.canonicalLink(names.world, `${kinds[link.type]}:${link.id}`, link.text,
          () => broker.translate(link.text, {resolveNames: false}));
    links.push({translation});
  }
  const translation = linkOnlyTranslation(request.text) ??
    await broker.translate(request.text, {glossary});
  await names.refresh(broker);
  if (generation !== names.generation || request.world !== names.world) {
    throw new Error('Legends paragraph world changed');
  }
  return validateParagraph(request, {translation, links});
}
