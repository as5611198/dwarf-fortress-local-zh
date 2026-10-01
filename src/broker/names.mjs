import { readFile, stat } from 'node:fs/promises';
import { tokenPattern, validateTranslation } from './safety.mjs';
import { captionRole, composeCaption } from './legends-captions.mjs';

const word = value => /[\p{L}\p{N}_]/u.test(value ?? '');
function makeIndex(aliases) {
  const root = new Map();
  for (const alias of aliases) {
    let branch = root;
    for (const char of alias) {
      if (!branch.has(char)) branch.set(char, new Map());
      branch = branch.get(char);
    }
    branch.value = alias;
  }
  return root;
}

export class WorldNames {
  constructor(path, dictionary = {}) {
    this.path = path;
    this.dictionary = dictionary;
    this.modified = null;
    this.entities = [];
    this.world = null;
    this.byAlias = new Map();
    this.byId = new Map();
    this.index = makeIndex(Object.keys(dictionary));
    this.baseGlossary = null;
    this.derived = new Set();
    this.generation = 0;
    this.loading = null;
  }
  async refresh(broker) {
    if (this.loading) return this.loading;
    if (!this.baseGlossary) this.baseGlossary = new Map(Object.entries(broker.glossary));
    this.loading = (async () => {
      let info;
      try { info = await stat(this.path); }
      catch (error) { if (error.code === 'ENOENT') return; throw error; }
      if (info.mtimeMs === this.modified) return;
      let data;
      try { data = JSON.parse(await readFile(this.path, 'utf8')); }
      catch (error) { if (error instanceof SyntaxError) return; throw error; }
      if (!Array.isArray(data.entities)) throw new Error('invalid world name registry');
      const entities = data.entities.filter(row => typeof row.id === 'string' &&
        typeof row.preferred === 'string' && row.preferred && Array.isArray(row.aliases) &&
        row.aliases.every(alias => typeof alias === 'string' && alias) &&
        (row.shortAliases === undefined || (Array.isArray(row.shortAliases) &&
          row.shortAliases.every(alias => typeof alias === 'string' && alias))));
      entities.sort((a, b) => (a.kind === 'first' ? 0 : 1) - (b.kind === 'first' ? 0 : 1));
      for (const alias of this.derived) {
        if (this.baseGlossary.has(alias)) broker.glossary[alias] = this.baseGlossary.get(alias);
        else delete broker.glossary[alias];
      }
      this.derived.clear();
      this.byAlias = new Map();
      this.byId = new Map(entities.map(row=>[row.id,row]));
      this.world = data.world;
      this.entities = entities;
      for (const row of entities) {
        for (const alias of row.aliases) {
          if (!this.byAlias.has(alias)) this.byAlias.set(alias, row);
        }
        if (row.kind === 'first' && this.dictionary[row.preferred] && !broker.glossary[row.preferred]) {
          broker.glossary[row.preferred] = validateTranslation(row.preferred, this.dictionary[row.preferred]);
          this.derived.add(row.preferred);
        }
      }
      this.index = makeIndex(new Set([...this.baseGlossary.keys(), ...this.byAlias.keys()]));
      this.generation++;
      this.modified = info.mtimeMs;
    })();
    try { await this.loading; } finally { this.loading = null; }
  }
  match(source) {
    const plain = source.replace(tokenPattern, ' ');
    const matches = [];
    for (let start = 0; start < plain.length; start++) {
      if (word(plain[start - 1])) continue;
      let branch = this.index;
      let longest;
      for (let end = start; end < plain.length; end++) {
        branch = branch.get(plain[end]);
        if (!branch) break;
        if (branch.value && !word(plain[end + 1])) longest = branch.value;
      }
      if (longest) {
        // Generated first names can collide with English articles (An -> 安).
        // In prose, only an explicit/full name may claim such an ambiguous token.
        if (!/^(?:A|An|The)$/i.test(longest) || plain.trim() === longest) matches.push(longest);
        start += longest.length - 1;
      }
    }
    return [...new Set(matches)];
  }
  async pinFigure(id, broker) {
    await this.refresh(broker);
    const row = id.startsWith('figure:') ? this.byId.get(id) : null;
    if (!row) return null;
    return this.canonical(row,broker);
  }
  canonical(row,broker) {
    const native = typeof row.nativeName==='string' && row.nativeName ? row.nativeName : null;
    if (native) {
      const first=native.split(/\s+/)[0];
      const glossary=this.dictionary[first] ? {[first]:this.dictionary[first]} : {};
      return broker.canonicalName(this.world,'native-v2:'+row.id,native,
        ()=>this.dictionary[native] ?? broker.phoneticName(native,glossary),{reuseExact:false});
    }
    return broker.canonicalName(this.world, row.id, row.preferred,
      () => row.aliases.map(alias => broker.glossary[alias]).find(Boolean) ??
        broker.translate(row.preferred, { resolveNames: false }));
  }
  async translateListName(request,broker) {
    await this.refresh(broker);
    if (request.world !== this.world) throw new Error('Legends list world mismatch');
    const row=this.byId.get(`${request.entityKind}:${request.entityId}`);
    if (!row || !row.aliases.includes(request.text) ||
        request.text !== (row.nativeName ?? row.aliases[0])) {
      throw new Error('Legends list identity mismatch');
    }
    const generation=this.generation;
    const translated=await this.canonical(row,broker);
    await this.refresh(broker);
    if (generation!==this.generation || request.world!==this.world) {
      throw new Error('Legends list world changed');
    }
    return validateTranslation(request.text,translated);
  }
  async translateCaption(request, broker, races) {
    await this.refresh(broker);
    if (request.world !== this.world) throw new Error('Legends caption world mismatch');
    const entity = this.byId.get(`figure:${request.figureId}`);
    const caption = { id: request.figureId, text: request.text };
    captionRole(caption, entity, races);
    const generation = this.generation;
    const canonical = await this.pinFigure(entity.id, broker);
    await this.refresh(broker);
    if (generation !== this.generation || request.world !== this.world) {
      throw new Error('Legends caption world changed');
    }
    return composeCaption(caption, entity, canonical, races);
  }
  async resolve(source, broker) {
    await this.refresh(broker);
    for (const alias of this.match(source)) {
      const row = this.byAlias.get(alias);
      if (!row) continue;
      const generation = this.generation;
      const canonical = await this.canonical(row,broker);
      if (generation !== this.generation) continue;
      for (const alias of row.aliases) {
        // Aliases share the same name, irrespective of which form the renderer sends.
        if (this.baseGlossary.has(alias)) continue;
        broker.glossary[alias] = validateTranslation(alias, canonical);
        this.derived.add(alias);
      }
    }
  }
}
