import crypto from 'node:crypto';

const NOTION_VERSION = '2025-09-03';

function text(property) {
  if (!property) return null;
  const values = property.title || property.rich_text || property.name || [];
  if (Array.isArray(values)) return values.map((item) => item.plain_text || item.text?.content || '').join('').trim() || null;
  return null;
}

function value(property) {
  if (!property) return null;
  if (property.type === 'title' || property.type === 'rich_text') return text(property);
  if (property.type === 'number') return property.number;
  if (property.type === 'url') return property.url;
  if (property.type === 'select') return property.select?.name || null;
  if (property.type === 'status') return property.status?.name || null;
  if (property.type === 'checkbox') return property.checkbox;
  if (property.type === 'date') return property.date?.start || null;
  if (property.type === 'multi_select') return property.multi_select?.map((item) => item.name).join(', ') || null;
  return text(property) || null;
}

function first(properties, names) {
  for (const name of names) {
    if (properties[name]) return value(properties[name]);
  }
  return null;
}

function slugify(input) {
  return String(input || '')
    .normalize('NFD').replace(/[\u0300-\u036f]/g, '')
    .toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') || null;
}

function notionHeaders() {
  return {
    Authorization: `Bearer ${process.env.NOTION_TOKEN}`,
    'Notion-Version': NOTION_VERSION,
    'Content-Type': 'application/json'
  };
}

async function queryNotionDataSource() {
  const pages = [];
  let cursor;
  do {
    const response = await fetch(`https://api.notion.com/v1/data_sources/${process.env.NOTION_DATA_SOURCE_ID}/query`, {
      method: 'POST', headers: notionHeaders(), body: JSON.stringify({ page_size: 100, ...(cursor ? { start_cursor: cursor } : {}) })
    });
    if (!response.ok) throw new Error(`Notion query failed: ${response.status} ${await response.text()}`);
    const data = await response.json();
    pages.push(...(data.results || []));
    cursor = data.has_more ? data.next_cursor : null;
  } while (cursor);
  return pages;
}

function mapPage(page) {
  const p = page.properties || {};
  const nome = first(p, ['Nome do Empreendimento', 'Nome', 'Name']) || `Lançamento ${page.id.slice(0, 8)}`;
  const status = first(p, ['Status']) || 'Ativo';
  const visibilidade = first(p, ['Visibilidade no site', 'Visibilidade']) || 'Rascunho';
  const publishedStatus = ['Ativo', 'Publicado'].includes(status) && ['Publicado', 'Ativo'].includes(visibilidade) ? 'Publicado' : 'Rascunho';
  const dataEntrega = first(p, ['Data de Entrega', 'Entrega']);
  return {
    notion_page_id: page.id,
    slug: first(p, ['Slug']) || slugify(nome),
    nome,
    status: ['Ativo', 'Pausado', 'Encerrado', 'Rascunho'].includes(status) ? status : 'Ativo',
    visibilidade_site: publishedStatus,
    categoria_comercial: first(p, ['Categoria comercial']),
    estado_imovel: first(p, ['Estado do imóvel']),
    origem_imovel: first(p, ['Origem do imóvel']),
    ja_foi_habitado: first(p, ['Já foi habitado?']) === true,
    bairro: first(p, ['Bairro', 'Região', 'Regiao']),
    endereco: first(p, ['Endereço', 'Endereco']),
    incorporadora: first(p, ['Incorporadora']),
    construtora: first(p, ['Construtora']),
    tipologia: first(p, ['Tipologia', 'Tipologias']),
    area: first(p, ['Área', 'Area']),
    preco_inicial: first(p, ['Valor Inicial', 'Preço Inicial', 'Preco Inicial']),
    preco_texto: first(p, ['Preço', 'Preco', 'Faixa de preço', 'Faixa de preco']),
    unidades_disponiveis: first(p, ['Unidades Disponiveis', 'Unidades Disponíveis']),
    unidades_texto: first(p, ['Unidades', 'Disponibilidade']),
    data_entrega: dataEntrega ? String(dataEntrega).slice(0, 10) : null,
    fase_obra: first(p, ['Fase da Obra', 'Fase']),
    descricao: first(p, ['Descrição', 'Descricao', 'Informações extras', 'Informacoes extras']),
    imagem_url: first(p, ['Imagem principal', 'Imagem', 'Imagem URL']),
    materiais_url: first(p, ['Link Drive ou Linktree', 'Materiais', 'Link de materiais']),
    pagina_url: `https://app.notion.com/p/${page.id.replaceAll('-', '')}`,
    destaque: Boolean(first(p, ['Destaque'])) || false,
    fonte: 'Notion'
  };
}

function verifySignature(rawBody, signature) {
  const token = process.env.NOTION_WEBHOOK_VERIFICATION_TOKEN;
  if (!token || !signature) return false;
  const expected = `sha256=${crypto.createHmac('sha256', token).update(rawBody).digest('hex')}`;
  if (expected.length !== signature.length) return false;
  return crypto.timingSafeEqual(Buffer.from(expected), Buffer.from(signature));
}

async function upsertSupabase(rows) {
  const response = await fetch(`${process.env.SUPABASE_URL}/rest/v1/lancamentos?on_conflict=notion_page_id`, {
    method: 'POST',
    headers: {
      apikey: process.env.SUPABASE_SERVICE_ROLE_KEY,
      Authorization: `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY}`,
      'Content-Type': 'application/json',
      Prefer: 'resolution=merge-duplicates,return=minimal'
    },
    body: JSON.stringify(rows)
  });
  if (!response.ok) throw new Error(`Supabase upsert failed: ${response.status} ${await response.text()}`);
}

export default async function handler(req, res) {
  if (req.method !== 'POST') return res.status(405).json({ error: 'Use POST' });
  const rawBody = typeof req.body === 'string' ? req.body : JSON.stringify(req.body || {});
  const payload = typeof req.body === 'string' ? JSON.parse(req.body) : req.body || {};

  // Notion envia este token uma única vez para verificar o endpoint.
  if (payload.verification_token) return res.status(200).json({ verification_token: payload.verification_token });

  const authorizedBySecret = process.env.SYNC_SECRET && req.headers['x-sync-secret'] === process.env.SYNC_SECRET;
  const authorizedByNotion = verifySignature(rawBody, req.headers['x-notion-signature']);
  if (!authorizedBySecret && !authorizedByNotion) return res.status(401).json({ error: 'Não autorizado' });

  try {
    const pages = await queryNotionDataSource();
    const rows = pages.map(mapPage).filter((row) => row.nome && row.slug);
    if (rows.length) await upsertSupabase(rows);
    return res.status(200).json({ ok: true, synchronized: rows.length });
  } catch (error) {
    console.error(error);
    return res.status(500).json({ error: 'Falha na sincronização' });
  }
}
