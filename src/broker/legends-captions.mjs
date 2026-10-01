import { cacheKey, POLICY_VERSION, validateTranslation } from './safety.mjs';

const titles = {
  'chaos follower': '混沌追隨者',
  'risen stalker': '復甦潛行者',
  necromancer: '死靈法師',
  bridegroom: '新郎',
  husband: '丈夫',
  wife: '妻子',
  consort: '伴侶',
  god: '男神',
  goddess: '女神',
  deity: '神祇',
};

export function translateRole(source, races) {
  if (source === 'force') return '力量';
  let role = source;
  let gender = '';
  if (role.startsWith('male ')) { gender = '男性'; role = role.slice(5); }
  else if (role.startsWith('female ')) { gender = '女性'; role = role.slice(7); }
  if (role.startsWith('dwarven ')) role = 'dwarf ' + role.slice(8);
  if (role === 'brute bride of twilight') return gender + '暮光蠻獸新娘';
  if (role === 'kelenken hen') return gender + '凱倫肯';
  if (role.endsWith(' woman') && !races[role]) role = role.slice(0, -6) + ' man';
  if (races[role]) return gender + races[role];
  for (const [title, translation] of Object.entries(titles)) {
    if (!role.endsWith(' ' + title)) continue;
    const race = role.slice(0, -title.length - 1);
    if (races[race]) return gender + races[race] + translation;
  }
  throw new Error(`unmapped Legends role: ${source}`);
}

const normalize = value => value.toLowerCase().replace(/[^\p{L}\p{N}]/gu, '');

export function captionRole(caption, entity, races) {
  const match = caption.text.match(/^(.*), "([^"]+)", (.+)$/);
  if (!match || entity?.id !== `figure:${caption.id}` ||
      ![match[1], match[2]].every(name => entity.aliases.some(alias => normalize(alias) === normalize(name)))) {
    throw new Error(`Legends caption identity mismatch: ${caption.id}`);
  }
  return translateRole(match[3], races);
}

export function composeCaption(caption, entity, canonical, races) {
  const role = captionRole(caption, entity, races);
  if (entity.nativeName) return validateTranslation(caption.text, `${canonical}，${role}`);
  return validateTranslation(caption.text, `${canonical}，「${canonical}」，${role}`);
}

export function indexPinnedFigures(journal, world, entities) {
  const figures = new Map(entities.filter(row => row.id.startsWith('figure:'))
    .map(row => [row.id, row.preferred]));
  const pinned = new Map();
  for (const line of journal.split('\n').filter(Boolean)) {
    let row, identity;
    try {
      row = JSON.parse(line);
      identity = JSON.parse(row.source);
    } catch { continue; }
    if (row.kind !== 'name' || row.policy !== POLICY_VERSION || row.language !== 'zh-Hant' ||
        !Array.isArray(identity) || identity.length !== 3 || identity[0] !== world ||
        figures.get(identity[1]) !== identity[2] ||
        row.key !== cacheKey(row.source, row.language, POLICY_VERSION + ':name')) continue;
    const translation = validateTranslation(identity[2], row.translation);
    if (pinned.has(identity[1]) && pinned.get(identity[1]) !== translation) {
      throw new Error(`conflicting figure name pin: ${identity[1]}`);
    }
    pinned.set(identity[1], translation);
  }
  return pinned;
}
