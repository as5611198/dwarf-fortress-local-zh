export function expandWorkbookAlternatives(row) {
  if (/[{}\[\]*]/.test(row.text+row.translation)) return null;
  const source=[...row.text.matchAll(/\(([^()]*(?:\/[^()]*)+)\)/g)];
  const target=[...row.translation.matchAll(/[（(]([^（）()]*(?:\/[^（）()]*)+)[）)]/g)];
  // Multi-group documents can reorder clauses: require explicit review for those.
  if(source.length!==1 || target.length!==1) return null;
  const inputs=source[0][1].split('/'),outputs=target[0][1].split('/');
  if(inputs.length!==outputs.length || inputs.some(value=>!value) || outputs.some(value=>!value)) return null;
  return inputs.map((value,index)=>({text:row.text.replace(source[0][0],value),
    translation:row.translation.replace(target[0][0],outputs[index])}));
}
