-- Libera a nova coluna de biografia sem ampliar as demais permissões do perfil.
grant update (biography) on table public.profiles to authenticated;

select setval(
  'public.cities_id_seq',
  greatest(coalesce((select max(id) from public.cities), 1), 1),
  true
);

select setval(
  'public.problem_categories_id_seq',
  greatest(coalesce((select max(id) from public.problem_categories), 1), 1),
  true
);

-- Cidades para validação dos filtros por estado e cidade.
insert into public.cities (name, state)
values
  ('Alumínio', 'sp'),
  ('Araçoiaba da Serra', 'sp'),
  ('Barueri', 'sp'),
  ('Campinas', 'sp'),
  ('Capela do Alto', 'sp'),
  ('Cotia', 'sp'),
  ('Guarulhos', 'sp'),
  ('Hortolândia', 'sp'),
  ('Indaiatuba', 'sp'),
  ('Iperó', 'sp'),
  ('Itu', 'sp'),
  ('Jaguariúna', 'sp'),
  ('Jundiaí', 'sp'),
  ('Mairinque', 'sp'),
  ('Mogi das Cruzes', 'sp'),
  ('Osasco', 'sp'),
  ('Paulínia', 'sp'),
  ('Piedade', 'sp'),
  ('Porto Feliz', 'sp'),
  ('Salto', 'sp'),
  ('Santo André', 'sp'),
  ('São Bernardo do Campo', 'sp'),
  ('São Caetano do Sul', 'sp'),
  ('São Paulo', 'sp'),
  ('São Roque', 'sp'),
  ('Sumaré', 'sp'),
  ('Tatuí', 'sp'),
  ('Valinhos', 'sp'),
  ('Vinhedo', 'sp'),
  ('Americana', 'sp'),
  ('Belo Horizonte', 'mg'),
  ('Belém', 'pa'),
  ('Brasília', 'df'),
  ('Campo Grande', 'ms'),
  ('Cuiabá', 'mt'),
  ('Florianópolis', 'sc'),
  ('Fortaleza', 'ce'),
  ('Goiânia', 'go'),
  ('Manaus', 'am'),
  ('Porto Alegre', 'rs'),
  ('Recife', 'pe'),
  ('Rio de Janeiro', 'rj'),
  ('Salvador', 'ba'),
  ('Vitória', 'es')
on conflict (name, state) do nothing;

insert into public.problem_categories (name, slug, description)
values
  ('Acessibilidade', 'accessibility', 'Barreiras e dificuldades de acesso em espaços públicos.'),
  ('Arborização', 'urban-trees', 'Poda, queda ou necessidade de manutenção de árvores.'),
  ('Educação', 'education', 'Problemas relacionados aos serviços públicos de educação.'),
  ('Habitação', 'housing', 'Questões de moradia e ocupação urbana.'),
  ('Iluminação pública', 'public-lighting', 'Lâmpadas apagadas, postes danificados e áreas sem iluminação.'),
  ('Limpeza urbana', 'urban-cleaning', 'Acúmulo de lixo, entulho e necessidade de limpeza pública.'),
  ('Meio ambiente', 'environment', 'Poluição, descarte irregular e danos ambientais.'),
  ('Obras e manutenção', 'public-maintenance', 'Obras públicas, calçadas e estruturas que precisam de manutenção.'),
  ('Proteção animal', 'animal-protection', 'Animais em risco, abandono e demandas de proteção animal.'),
  ('Saneamento', 'sanitation', 'Água, esgoto, drenagem e saneamento básico.'),
  ('Saúde pública', 'public-health', 'Problemas relacionados aos serviços públicos de saúde.'),
  ('Trânsito', 'traffic', 'Sinalização, semáforos e organização do trânsito.'),
  ('Transporte público', 'public-transport', 'Ônibus, pontos e qualidade do transporte coletivo.')
on conflict (slug) do update
set name = excluded.name,
    description = excluded.description;

notify pgrst, 'reload schema';
