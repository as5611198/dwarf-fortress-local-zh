import { tokenPattern, validateTranslation } from './safety.mjs';

const escape = value => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const word = value => /[\p{L}\p{N}_]/u.test(value ?? '');

export function prepareTemplate(source, glossary = {}, numericTemplates = true) {
  // Boundary formatting belongs to the renderer; translate and cache only its prose.
  const boundary = String.raw`(?:\[C:[0-7]:[0-7]:[01]\]|\[[BPR]\])`;
  const prefix = source.match(new RegExp(`^${boundary}+`))?.[0] ?? '';
  const remainder = source.slice(prefix.length);
  const suffix = remainder.match(new RegExp(`${boundary}+$`))?.[0] ?? '';
  const core = remainder.slice(0, remainder.length - suffix.length);
  if ((prefix || suffix) && core.trim()) {
    const inner = prepareTemplate(core, glossary, numericTemplates);
    return { ...inner, restore: value => validateTranslation(source, prefix + inner.restore(value) + suffix) };
  }
  // Never interpret existing formatting tokens as names or numeric slots.
  if (/\{\{DF[NE]\d+\}\}/.test(source)) return { source, kind: 'exact', restore: value => validateTranslation(source, value) };
  const names = Object.keys(glossary).filter(name => name && typeof glossary[name] === 'string').sort((a, b) => b.length - a.length);
  const pattern = new RegExp(`${tokenPattern.source}${names.length ? '|' + names.map(escape).join('|') : ''}${numericTemplates ? '|\\d+(?:[.,]\\d+)*' : ''}`, 'g');
  const numbers = [], entities = [], years = new Set();
  const template = source.replace(pattern, (part, offset) => {
    if (new RegExp(`^(?:${tokenPattern.source})$`).test(part)) return part;
    if (Object.hasOwn(glossary, part)) {
      if (word(source[offset - 1]) || word(source[offset + part.length])) return part;
      entities.push(validateTranslation(part, glossary[part]));
      return `{{DFE${entities.length - 1}}}`;
    }
    if (/^In (?:the [a-z ]+ of )?$/i.test(source.slice(0, offset))) years.add(numbers.length);
    numbers.push(part);
    return `{{DFN${numbers.length - 1}}}`;
  });
  const nameFragment = template.replace(/\b(?:the|an?)\s+(?=\{\{DFE\d+\}\})/gi, '');
  return {
    source: template,
    kind: entities.length ? 'entity' : numbers.length ? 'numeric' : 'exact',
    restore: value => validateTranslation(source, value.replace(/\{\{DF([NE])(\d+)\}\}/g,
      (token, type, i, offset, translated) => {
        const index = Number(i);
        const restored = (type === 'N' ? numbers : entities)[index] ?? token;
        return type === 'N' && years.has(index) && !/^\s*年/.test(translated.slice(offset + token.length))
          ? restored + '年' : restored;
      })),
    literal: template === 'd. {{DFN0}}' ? '卒於{{DFN0}}年'
      : !/\p{L}/u.test(nameFragment.replace(tokenPattern, '')) ? nameFragment : null,
  };
}
