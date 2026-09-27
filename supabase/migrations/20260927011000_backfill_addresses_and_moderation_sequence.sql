-- Completa os enderecos dos reportes existentes no ambiente de validacao.
-- Reportes novos passam a persistir esses campos diretamente pelo aplicativo.

update public.posts
set street = 'Rua Belo Horizonte', neighborhood = 'Jardim Nogueira'
where id = 14
  and latitude = -23.4789184902588
  and longitude = -47.4933483917677
  and street is null
  and neighborhood is null;

update public.posts
set street = 'Rua Júpiter', neighborhood = 'Jardim Baronesa'
where id = 15
  and latitude = -23.4830483070411
  and longitude = -47.4902759621689
  and street is null
  and neighborhood is null;

update public.posts
set street = 'Rua Nelson Herdy Barbosa', neighborhood = 'Vila Formosa'
where id = 30
  and latitude = -23.4640940854684
  and longitude = -47.4759805580837
  and street is null
  and neighborhood is null;

update public.posts
set street = 'Rua José Assad Atalla', neighborhood = 'Portal Ville Jardins'
where id in (25, 26, 27)
  and latitude = -23.2937
  and longitude = -47.6641
  and street is null
  and neighborhood is null;

update public.posts
set street = 'Rua Professor Antônio Firmino Proença',
    neighborhood = 'Bairro do Caguassu'
where id = 20
  and latitude = -23.4493854
  and longitude = -47.4980995
  and street is null
  and neighborhood is null;

update public.posts
set street = 'Rua Bayard Nobrega de Almeida',
    neighborhood = 'Jardim Prestes de Barros'
where id = 28
  and latitude = -23.5107817827735
  and longitude = -47.430363163977
  and street is null
  and neighborhood is null;

update public.posts
set street = 'Rua Francisco Otaviano', neighborhood = 'Vila Haro'
where id = 31
  and latitude = -23.5008007369049
  and longitude = -47.4346690093997
  and street is null
  and neighborhood is null;

update public.posts
set street = 'Rua Aparecida', neighborhood = 'Jardim Santa Rosália'
where id = 29
  and latitude = -23.4910939713472
  and longitude = -47.4545862950856
  and street is null
  and neighborhood is null;

grant usage, select on sequence public.moderation_reports_id_seq to authenticated;
