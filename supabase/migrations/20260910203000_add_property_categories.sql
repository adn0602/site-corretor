-- Separação comercial: lançamentos, estoque novo pronto e imóveis prontos usados.
-- Aplicar depois da migration base de lancamentos/leads.

alter table public.lancamentos
  add column if not exists categoria_comercial text,
  add column if not exists estado_imovel text,
  add column if not exists origem_imovel text,
  add column if not exists ja_foi_habitado boolean;

alter table public.lancamentos
  drop constraint if exists lancamentos_categoria_comercial_check;
alter table public.lancamentos
  add constraint lancamentos_categoria_comercial_check
  check (categoria_comercial is null or categoria_comercial in ('Lançamento', 'Estoque novo pronto', 'Imóvel pronto usado'));

alter table public.lancamentos
  drop constraint if exists lancamentos_estado_imovel_check;
alter table public.lancamentos
  add constraint lancamentos_estado_imovel_check
  check (estado_imovel is null or estado_imovel in ('Em construção', 'Novo nunca habitado', 'Usado'));

alter table public.lancamentos
  drop constraint if exists lancamentos_origem_imovel_check;
alter table public.lancamentos
  add constraint lancamentos_origem_imovel_check
  check (origem_imovel is null or origem_imovel in ('Incorporadora', 'Construtora', 'Proprietário', 'Imobiliária', 'Captação própria'));

create index if not exists lancamentos_categoria_comercial_idx
  on public.lancamentos (categoria_comercial, visibilidade_site, status);

comment on column public.lancamentos.categoria_comercial is 'Lançamento, Estoque novo pronto ou Imóvel pronto usado.';
comment on column public.lancamentos.estado_imovel is 'Em construção, Novo nunca habitado ou Usado.';
comment on column public.lancamentos.origem_imovel is 'Incorporadora, Construtora, Proprietário, Imobiliária ou Captação própria.';
comment on column public.lancamentos.ja_foi_habitado is 'Diferencia estoque novo de imóvel pronto usado.';

-- Não preencher automaticamente: a base Imóveis - Prontos contém casos misturados.
-- Classifique cada registro após confirmar se já teve moradores.
