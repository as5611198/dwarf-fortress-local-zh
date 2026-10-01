export function composeRawState(source, { creatures, plants, reviewed }) {
  const state = /^(frozen|boiling|melted) (.+)$/.exec(source);
  const base = state ? state[2] : source;
  const creature = name => creatures.get(name) ??
    creatures.get(name[0].toUpperCase() + name.slice(1)) ?? reviewed.get(name);
  let translation, basis, pattern;
  for (const [suffix, zh] of [
    [' cheese powder', '乳酪粉'],
    [' cheese', '乳酪'],
    ["'s milk", '奶'],
    [' milk', '奶'],
    [' venom', '毒液'],
  ]) {
    if (!base.endsWith(suffix)) continue;
    basis = base.slice(0, -suffix.length);
    const name = creature(basis);
    if (name) { translation = name + zh; pattern = suffix.trim(); }
    break;
  }
  if (!translation && base.endsWith(' wood')) {
    basis = `${base.slice(0, -5)} tree`;
    const tree = plants.get(basis);
    if (tree?.endsWith('樹')) { translation = `${tree.slice(0, -1)}木材`; pattern = 'wood'; }
  }
  if (!translation && reviewed.has(base)) {
    translation = reviewed.get(base);
    basis = base;
    pattern = 'reviewed';
  }
  if (!translation) return null;
  const prefix = { frozen: '冰凍', boiling: '沸騰', melted: '融化的' }[state?.[1]] ?? '';
  return { translation: prefix + translation, basis, pattern };
}

export function selectRawStateSources(rows, excluded = new Set()) {
  const unique = new Map();
  const excludedLower = new Set([...excluded].map(key => key.toLowerCase()));
  for (const row of rows) {
    if (row.token !== 'STATE_NAME' && !row.tokens?.includes('STATE_NAME')) continue;
    if (excludedLower.has(row.text.toLowerCase())) continue;
    const mods = unique.get(row.text)?.mods ?? [];
    for (const mod of row.mods ?? [row.mod]) {
      if (mod && !mods.includes(mod)) mods.push(mod);
    }
    unique.set(row.text, { text: row.text, mods });
  }
  return [...unique.values()];
}
