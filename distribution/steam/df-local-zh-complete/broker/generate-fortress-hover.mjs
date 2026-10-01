import { readFile,writeFile } from 'node:fs/promises';
import { parse } from 'csv-parse/sync';
import { validateTranslation } from './safety.mjs';
const rows=parse(await readFile(new URL('./data/fortress-ui.csv',import.meta.url),'utf8'),{columns:true});
const translations={};
for(const row of rows) translations[row.text]=validateTranslation(row.text,row.translation);
await writeFile(new URL('./data/fortress-hover.json',import.meta.url),JSON.stringify({version:1,translations})+'\n','utf8');
console.log(`FORTRESS HOVER ${Object.keys(translations).length} reviewed phrases`);
