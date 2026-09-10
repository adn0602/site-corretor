-- SETUP COMPLETO DO SUPABASE — SITE CORRETOR
-- Execute este arquivo inteiro no SQL Editor do projeto correto.
-- Ele cria o catálogo, os leads, RLS, índices e categorias comerciais.

create extension if not exists pgcrypto;

create table if not exists public.lancamentos (
  id uuid primary key default gen_random_uuid(),
  notion_page_id text unique,
  slug text not null unique,
  nome text not null,
  status text not null default 'Ativo' check (status in ('Ativo', 'Pausado', 'Encerrado', 'Rascunho')),
  visibilidade_site text not null default 'Rascunho' check (visibilidade_site in ('Rascunho', 'Em revisão', 'Publicado', 'Pausado')),
  categoria_comercial text check (categoria_comercial is null or categoria_comercial in ('Lançamento', 'Estoque novo pronto', 'Imóvel pronto usado')),
  estado_imovel text check (estado_imovel is null or estado_imovel in ('Em construção', 'Novo nunca habitado', 'Usado')),
  origem_imovel text check (origem_imovel is null or origem_imovel in ('Incorporadora', 'Construtora', 'Proprietário', 'Imobiliária', 'Captação própria')),
  ja_foi_habitado boolean,
  bairro text,
  endereco text,
  incorporadora text,
  construtora text,
  tipologia text,
  area text,
  preco_inicial numeric(14,2),
  preco_texto text,
  unidades_disponiveis integer,
  unidades_texto text,
  data_entrega date,
  fase_obra text,
  descricao text,
  imagem_url text,
  galeria_urls jsonb not null default '[]'::jsonb check (jsonb_typeof(galeria_urls) = 'array'),
  materiais_url text,
  pagina_url text,
  destaque boolean not null default false,
  ordem_destaque integer not null default 0,
  fonte text not null default 'Notion',
  atualizado_em timestamptz not null default now(),
  criado_em timestamptz not null default now()
);

create index if not exists lancamentos_publicados_idx
  on public.lancamentos (visibilidade_site, status, destaque, ordem_destaque);
create index if not exists lancamentos_bairro_idx
  on public.lancamentos (bairro);
create index if not exists lancamentos_categoria_comercial_idx
  on public.lancamentos (categoria_comercial, visibilidade_site, status);

create table if not exists public.leads_do_site (
  id uuid primary key default gen_random_uuid(),
  criado_em timestamptz not null default now(),
  nome text not null check (char_length(trim(nome)) between 2 and 120),
  whatsapp text not null check (char_length(trim(whatsapp)) between 8 and 40),
  email text check (email is null or char_length(trim(email)) <= 254),
  interesse text,
  regiao text,
  orcamento text,
  empreendimento text,
  empreendimento_slug text,
  url_da_pagina text,
  fonte text not null default 'site',
  observacoes text,
  status_atendimento text not null default 'Novo' check (status_atendimento in ('Novo', 'Em contato', 'Visita agendada', 'Proposta', 'Negociação', 'Convertido', 'Perdido')),
  atualizado_em timestamptz not null default now()
);

-- Compatibilidade com tabelas criadas em uma execução anterior.
-- CREATE TABLE IF NOT EXISTS não altera uma tabela que já existe.
alter table public.leads_do_site add column if not exists criado_em timestamptz not null default now();
alter table public.leads_do_site add column if not exists nome text;
alter table public.leads_do_site add column if not exists whatsapp text;
alter table public.leads_do_site add column if not exists email text;
alter table public.leads_do_site add column if not exists interesse text;
alter table public.leads_do_site add column if not exists regiao text;
alter table public.leads_do_site add column if not exists orcamento text;
alter table public.leads_do_site add column if not exists empreendimento text;
alter table public.leads_do_site add column if not exists empreendimento_slug text;
alter table public.leads_do_site add column if not exists url_da_pagina text;
alter table public.leads_do_site add column if not exists fonte text not null default 'site';
alter table public.leads_do_site add column if not exists observacoes text;
alter table public.leads_do_site add column if not exists status_atendimento text not null default 'Novo';
alter table public.leads_do_site add column if not exists atualizado_em timestamptz not null default now();

-- Garante os campos novos do catálogo mesmo se lancamentos já existir.
alter table public.lancamentos add column if not exists categoria_comercial text;
alter table public.lancamentos add column if not exists estado_imovel text;
alter table public.lancamentos add column if not exists origem_imovel text;
alter table public.lancamentos add column if not exists ja_foi_habitado boolean;

create index if not exists leads_do_site_criado_em_idx
  on public.leads_do_site (criado_em desc);
create index if not exists leads_do_site_status_idx
  on public.leads_do_site (status_atendimento);
create index if not exists leads_do_site_empreendimento_idx
  on public.leads_do_site (empreendimento_slug);

create or replace function public.definir_atualizado_em()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  new.atualizado_em = now();
  return new;
end;
$$;

drop trigger if exists lancamentos_definir_atualizado_em on public.lancamentos;
create trigger lancamentos_definir_atualizado_em
before update on public.lancamentos
for each row execute function public.definir_atualizado_em();

drop trigger if exists leads_do_site_definir_atualizado_em on public.leads_do_site;
create trigger leads_do_site_definir_atualizado_em
before update on public.leads_do_site
for each row execute function public.definir_atualizado_em();

alter table public.lancamentos enable row level security;
alter table public.leads_do_site enable row level security;

drop policy if exists "Lançamentos publicados são públicos" on public.lancamentos;
create policy "Lançamentos publicados são públicos"
on public.lancamentos for select to anon, authenticated
using (visibilidade_site = 'Publicado' and status = 'Ativo');

drop policy if exists "Site pode criar leads" on public.leads_do_site;
create policy "Site pode criar leads"
on public.leads_do_site for insert to anon, authenticated
with check (fonte = 'site');

drop policy if exists "Usuários autenticados administram lançamentos" on public.lancamentos;
create policy "Usuários autenticados administram lançamentos"
on public.lancamentos for all to authenticated
using (true) with check (true);

drop policy if exists "Usuários autenticados administram leads" on public.leads_do_site;
create policy "Usuários autenticados administram leads"
on public.leads_do_site for all to authenticated
using (true) with check (true);

comment on table public.lancamentos is 'Catálogo de empreendimentos sincronizado com Notion.';
comment on table public.leads_do_site is 'Leads enviados pelo formulário público do site; leitura pública bloqueada.';

-- Verificação final
select table_name
from information_schema.tables
where table_schema = 'public'
  and table_name in ('lancamentos', 'leads_do_site')
order by table_name;

select column_name, data_type
from information_schema.columns
where table_schema = 'public'
  and table_name in ('lancamentos', 'leads_do_site')
order by table_name, ordinal_position;
