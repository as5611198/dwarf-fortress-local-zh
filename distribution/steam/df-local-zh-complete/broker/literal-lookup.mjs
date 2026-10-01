// Only derive names from explicitly tagged species, never arbitrary personal names.
export function lookupLiteral(source,literals,creatures) {
  const prefix=/^(?:\[C:\d+:\d+:\d+\])+/.exec(source)?.[0] ?? '';
  let body=source.slice(prefix.length);
  // Keyboard hints and display dimensions are identifiers, never prose or names.
  const key='(?:[A-Za-z0-9]|ESC|Enter|Return|Tab|Space|Delete|Backspace|F(?:[1-9]|1[0-2]))';
  if(new RegExp(`^(?:(?:Ctrl|Control|Alt|Shift)\\+)+${key}$`,'i').test(body) ||
      new RegExp(`^${key}:\\s*$`,'i').test(body) || /^\d+\s*x\s*\d+$/i.test(body)) return source;
  const numbered=body.length<=200 && /^(.*?) ([0-9]+)$/.exec(body);
  if(numbered) {
    const species=creatures.get(numbered[1]) ?? creatures.get(numbered[1].toLowerCase());
    if(species) return prefix+species+' '+numbered[2];
  }
  let dot='';
  if(body==='.Needs setting') {dot='.';body=body.slice(1);}
  const literal=literals.get(body);
  if(literal!==undefined) return prefix+dot+literal;
  const quality=/^\{([^{}]+)\}$/.exec(body);
  if(quality && literals.has(quality[1])) return prefix+'{'+literals.get(quality[1])+'}';
  return literals.get(source);
}
