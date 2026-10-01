import * as OpenCC from 'opencc-js';

const convert=OpenCC.Converter({from:'tw',to:'cn'});
export const simplify=value=>convert(value);
export function simplifyTree(value) {
  if(typeof value==='string') return simplify(value);
  if(Array.isArray(value)) return value.map(simplifyTree);
  if(value && typeof value==='object') return Object.fromEntries(Object.entries(value).map(([key,row])=>[key,simplifyTree(row)]));
  return value;
}
