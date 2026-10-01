const dyeParts = [
  ['bark', '樹皮'], ['leaf', '葉'], ['cone', '球果'], ['shell', '殼'],
  ['skin', '皮'], ['peel', '果皮'], ['hull', '外殼'], ['rind', '果皮'],
  ['bean', '豆'], ['husk', '殼'],
];

export function composeReactionName(source, plants) {
  const match = /^make (.+) dye$/.exec(source);
  if (!match) return null;
  let name = match[1];
  let part = '';
  for (const [suffix, translation] of dyeParts) {
    if (!name.endsWith(` ${suffix}`)) continue;
    name = name.slice(0, -(suffix.length + 1));
    part = translation;
    break;
  }
  const direct = plants.get(name);
  const plant = direct ?? plants.get(`${name} tree`);
  if (!plant) return null;
  const trimTree = plant.endsWith('樹') && (!direct || part === '樹皮' || part === '外殼');
  const base = trimTree ? plant.slice(0, -1) : plant;
  return { translation: `製作${base}${part}染料`, basis: name, pattern: part || 'whole' };
}
