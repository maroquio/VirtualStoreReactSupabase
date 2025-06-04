# Documentação Completa do Script SQL E-commerce

## Índice

1. [Configuração Inicial e Extensões](#1-configuração-inicial-e-extensões)
2. [Criação dos Tipos ENUM](#2-criação-dos-tipos-enum)
3. [Funções de Validação](#3-funções-de-validação)
4. [Criação das Tabelas](#4-criação-das-tabelas)
5. [Funções Auxiliares e Triggers](#5-funções-auxiliares-e-triggers)
6. [Sistema de Auditoria](#6-sistema-de-auditoria)
7. [Criação Automática de Profile](#7-criação-automática-de-profile)
8. [Row Level Security (RLS)](#8-row-level-security-rls)
9. [Políticas de Segurança](#9-políticas-de-segurança)
10. [Storage Buckets](#10-storage-buckets)
11. [Índices para Performance](#11-índices-para-performance)
12. [Dados Iniciais](#12-dados-iniciais)
13. [Views Úteis](#13-views-úteis)
14. [Funções Utilitárias](#14-funções-utilitárias)

---

## 1. Configuração Inicial e Extensões

### CREATE EXTENSION IF NOT EXISTS "uuid-ossp"

Esta extensão adiciona funções para gerar UUIDs (Universally Unique Identifiers) no PostgreSQL. UUIDs são identificadores únicos de 128 bits que são extremamente úteis em sistemas distribuídos, pois podem ser gerados de forma independente em diferentes servidores sem risco de colisão. No contexto deste e-commerce, os UUIDs são usados principalmente para identificar usuários de forma única, garantindo que cada usuário tenha um ID globalmente único que pode ser sincronizado com o sistema de autenticação do Supabase.

### CREATE EXTENSION IF NOT EXISTS "pgcrypto"

A extensão pgcrypto fornece funções criptográficas para o PostgreSQL, incluindo hashing, criptografia simétrica e assimétrica. Embora não seja diretamente utilizada neste script, ela é essencial para operações de segurança como hash de senhas, geração de tokens seguros e criptografia de dados sensíveis. Sua inclusão prepara o banco de dados para futuras implementações de segurança, como criptografia de dados de cartão de crédito ou informações pessoais sensíveis dos clientes.

---

## 2. Criação dos Tipos ENUM

### CREATE TYPE order_status_enum

Este comando cria um tipo enumerado personalizado que define todos os possíveis estados de um pedido no sistema. O uso de ENUM garante integridade de dados ao restringir os valores possíveis para o campo de status, evitando erros de digitação ou valores inválidos. Os status seguem o fluxo natural de um pedido de e-commerce: Cart (carrinho), Ordered (pedido feito), Paid (pago), Preparing (preparando), Shipped (enviado), Received (recebido), Cancelled (cancelado), Returned (devolvido) e Refunded (reembolsado). Esta abordagem também melhora a performance das consultas e economiza espaço de armazenamento comparado a strings livres.

### CREATE TYPE audit_action_enum

Define os tipos de ações que podem ser registradas no sistema de auditoria. Este ENUM garante que apenas operações válidas (INSERT, UPDATE, DELETE, SELECT) sejam registradas na tabela de auditoria. Isso é fundamental para manter um log consistente e confiável de todas as operações realizadas no banco de dados, facilitando a investigação de problemas, conformidade regulatória e análise de comportamento do sistema.

### CREATE TYPE brazilian_state_enum

Cria um tipo enumerado contendo todas as siglas dos estados brasileiros. Esta implementação específica para o Brasil garante que apenas estados válidos sejam inseridos nos endereços, prevenindo erros de digitação e padronizando o formato dos dados. Isso é especialmente importante para integração com APIs de correios, cálculo de frete e relatórios regionais de vendas.

---

## 3. Funções de Validação

### CREATE FUNCTION validate_postal_code

Esta função implementa a validação de CEPs brasileiros, removendo caracteres não numéricos e verificando se o resultado tem exatamente 8 dígitos. A função é marcada como IMMUTABLE, indicando que sempre retornará o mesmo resultado para os mesmos parâmetros, permitindo otimizações do PostgreSQL. A validação de CEP é crucial para garantir a correta entrega de produtos e integração com serviços de cálculo de frete, além de prevenir erros de entrada de dados que poderiam causar problemas logísticos.

### CREATE FUNCTION validate_phone

Implementa validação robusta para números de telefone brasileiros, aceitando tanto números fixos quanto celulares. A função remove todos os caracteres não numéricos e verifica se o formato corresponde aos padrões brasileiros (com DDD e 8 ou 9 dígitos). Esta validação é essencial para garantir que os clientes possam ser contactados para questões de entrega, suporte ou marketing, e que os números estejam em formato válido para integração com sistemas de SMS ou WhatsApp.

### CREATE FUNCTION validate_email

Valida endereços de email usando uma expressão regular que verifica a estrutura básica de um email válido. A função é case-insensitive (não diferencia maiúsculas de minúsculas) e garante que o email tenha o formato correto com nome de usuário, símbolo @, domínio e extensão. A validação de email é fundamental para comunicação com clientes, recuperação de senha, notificações de pedidos e marketing por email.

---

## 4. Criação das Tabelas

### CREATE TABLE profiles

A tabela profiles é o coração do sistema de usuários, estendendo a tabela auth.users do Supabase com informações adicionais específicas do e-commerce. Ela usa o mesmo UUID da tabela de autenticação como chave primária, criando uma relação 1:1 com CASCADE DELETE para garantir que quando um usuário é removido do sistema de autenticação, seu perfil também seja excluído. Os campos incluem informações pessoais (nome completo, telefone), avatar_url para foto de perfil, e o importante campo is_admin que determina privilégios administrativos. As constraints garantem validação de email e telefone, além de impedir nomes vazios.

### CREATE TABLE categories

Define a estrutura para categorização de produtos, fundamental para organização e navegação no e-commerce. Cada categoria tem um ID auto-incrementado, nome único (garantido por UNIQUE constraint), descrição opcional e flag is_active para desativação soft delete. A constraint de nome não vazio garante que toda categoria tenha uma identificação válida. Esta tabela permite hierarquização futura de categorias e facilita filtros de busca e navegação por departamentos.

### CREATE TABLE carriers

Armazena informações sobre transportadoras disponíveis para entrega. A estrutura simples com nome único permite fácil expansão futura para incluir informações como prazos, custos base, áreas de cobertura e integrações com APIs de rastreamento. O campo is_active permite desativar temporariamente transportadoras sem perder histórico de pedidos antigos.

### CREATE TABLE products

A tabela central do catálogo de produtos com campos essenciais para um e-commerce: título, descrição, preço (com validação para não aceitar valores negativos), URL da imagem, categoria (com chave estrangeira), controle de estoque e flag de ativo/inativo. O campo stock_quantity com constraint CHECK garante que o estoque nunca seja negativo, prevenindo vendas impossíveis. Os timestamps de criação e atualização permitem rastreamento de mudanças e ordenação por novidades.

### CREATE TABLE addresses

Gerencia múltiplos endereços por cliente, essencial para flexibilidade na entrega. A estrutura contempla todos os campos necessários para endereçamento brasileiro, incluindo validação de CEP e estado através do enum brazilian_state_enum. O campo is_default permite que o cliente defina um endereço principal, melhorando a experiência de compra. A chave estrangeira com CASCADE DELETE garante que endereços sejam removidos quando o usuário é excluído.

### CREATE TABLE orders

A tabela mais complexa do sistema, armazenando todos os dados do pedido incluindo valores (pedido, frete e total calculado automaticamente), informações de entrega, transportadora e endereço completo (desnormalizado para manter histórico mesmo se o endereço original for alterado). O campo total_value é GENERATED ALWAYS AS STORED, calculando automaticamente a soma do valor do pedido com o frete. As constraints garantem valores não negativos e validação do telefone do destinatário.

### CREATE TABLE order_statuses

Implementa um histórico completo de status dos pedidos, permitindo rastreabilidade total das mudanças. A chave primária composta (order_id, status) impede status duplicados para o mesmo pedido. Cada entrada registra quando a mudança ocorreu, quem a fez (changed_by) e notas opcionais. Esta abordagem permite análises de tempo entre etapas, identificação de gargalos e auditoria completa do ciclo de vida dos pedidos.

### CREATE TABLE order_items

Armazena os produtos de cada pedido com quantidade, valor unitário no momento da compra (importante para manter histórico de preços) e valor total calculado automaticamente. A chave primária composta impede produtos duplicados no mesmo pedido. As constraints garantem quantidades positivas e valores não negativos. Esta estrutura permite que produtos mudem de preço sem afetar pedidos anteriores.

### CREATE TABLE audit_log

Tabela fundamental para conformidade e segurança, registrando todas as operações realizadas nas tabelas monitoradas. Armazena a tabela afetada, ID do registro, tipo de ação, valores antes e depois (em formato JSONB para flexibilidade), usuário responsável, timestamp e informações de conexão (IP e user agent para investigações de segurança). O uso de JSONB permite armazenar estruturas complexas e fazer queries eficientes sobre os dados históricos.

---

## 5. Funções Auxiliares e Triggers

### CREATE FUNCTION update_updated_at_column

Função trigger genérica que atualiza automaticamente o campo updated_at sempre que um registro é modificado. Esta padronização garante que todas as tabelas com este campo tenham comportamento consistente, facilitando rastreamento de mudanças e sincronização de dados. A simplicidade da função (apenas atribui NOW() ao campo) a torna reutilizável e eficiente para múltiplas tabelas.

### CREATE TRIGGER update_profiles_updated_at / products / orders

Estes triggers aplicam a função update_updated_at_column às respectivas tabelas, garantindo que o timestamp de última modificação seja sempre atualizado automaticamente. O uso de BEFORE UPDATE garante que a modificação ocorra antes da gravação no banco, evitando uma operação adicional. Esta automação elimina a necessidade de gerenciar manualmente estes timestamps na aplicação.

### CREATE FUNCTION create_initial_order_status

Automatiza a criação do status inicial 'Cart' quando um novo pedido é criado. Esta função garante que todo pedido comece com o status correto e tenha pelo menos um registro na tabela order_statuses. Isso simplifica a lógica da aplicação e garante consistência no fluxo de pedidos. O campo changed_by é preenchido com o ID do cliente, registrando quem iniciou o pedido.

### CREATE FUNCTION is_order_in_cart_status

Função de verificação que determina se um pedido está atualmente no status 'Cart'. Usa uma subquery para encontrar o status mais recente (maior datetime) e verifica se é 'Cart'. Esta função é fundamental para as políticas de segurança RLS, permitindo que usuários só modifiquem pedidos que ainda estão em carrinho. O SECURITY DEFINER permite que a função acesse dados mesmo quando chamada por usuários com permissões limitadas.

### CREATE FUNCTION get_latest_order_status

Retorna o status atual de um pedido consultando o registro mais recente na tabela order_statuses. Esta função centraliza a lógica de obtenção de status, evitando queries complexas repetidas throughout a aplicação. É amplamente usada em views, outras funções e políticas de segurança para determinar o estado atual de pedidos.

### CREATE FUNCTION user_is_admin

Função crítica de segurança que verifica se o usuário atual (obtido via auth.uid()) tem privilégios administrativos. Marcada como STABLE (resultado pode mudar entre transações) e SECURITY DEFINER (executa com privilégios do criador), esta função é a base para todas as políticas de segurança que diferenciam admins de usuários comuns. Sua simplicidade e eficiência a tornam ideal para uso frequente em políticas RLS.

### CREATE FUNCTION validate_status_transition

Implementa a máquina de estados do pedido, definindo quais transições de status são válidas. A função usa um array bidimensional para mapear transições permitidas (por exemplo, de 'Cart' para 'Ordered', mas não de 'Shipped' para 'Cart'). Esta validação centralizada garante que o fluxo de pedidos siga regras de negócio consistentes, prevenindo estados inválidos que poderiam causar problemas logísticos ou financeiros.

### CREATE FUNCTION process_order_stock

Gerencia o controle de estoque quando um pedido é fechado. A função primeiro verifica se há estoque suficiente para todos os itens do pedido, registrando avisos para produtos sem estoque. Se houver estoque suficiente, deduz as quantidades dos produtos. O retorno booleano indica sucesso ou falha, permitindo que a transação seja abortada se não houver estoque. Esta abordagem previne vendas de produtos indisponíveis e mantém o estoque sempre atualizado.

### CREATE FUNCTION ensure_single_default_address

Garante que cada cliente tenha no máximo um endereço padrão. Quando um endereço é marcado como padrão, a função automaticamente desmarca todos os outros endereços do mesmo cliente. Esta lógica simplifica a gestão de endereços e melhora a experiência do usuário ao garantir sempre um endereço principal claramente definido.

### CREATE FUNCTION update_order_value

Mantém o valor total do pedido sincronizado com a soma dos seus itens. Acionada por mudanças na tabela order_items (INSERT, UPDATE, DELETE), recalcula o total e atualiza a tabela orders. O tratamento especial para DELETE (usando OLD em vez de NEW) garante funcionamento correto para todas as operações. Esta automação elimina inconsistências entre itens e total do pedido.

### CREATE FUNCTION prevent_unauthorized_admin_change

Função de segurança que impede que usuários não-admin alterem o campo is_admin. Usando OLD e NEW no contexto do trigger, verifica se houve tentativa de mudança e reverte se o usuário não for admin. Esta camada adicional de segurança complementa as políticas RLS, garantindo que privilégios administrativos só possam ser concedidos por outros administradores.

---

## 6. Sistema de Auditoria

### CREATE FUNCTION audit_trigger_function

Implementa um sistema completo de auditoria que registra todas as operações (INSERT, UPDATE, DELETE) nas tabelas monitoradas. A função é inteligente o suficiente para lidar com tabelas que têm chaves compostas (como order_statuses e order_items), construindo IDs únicos concatenados. O uso de JSONB para armazenar valores permite flexibilidade total e consultas eficientes sobre dados históricos. O SECURITY DEFINER garante que a auditoria funcione mesmo para usuários com permissões limitadas.

### CREATE TRIGGER audit_profiles/orders/order_items/order_statuses/products

Estes triggers aplicam a função de auditoria às tabelas principais do sistema. Executando AFTER cada operação, garantem que a auditoria capture o estado final das mudanças. A cobertura abrangente permite rastreamento completo de todas as ações críticas do sistema, essencial para conformidade regulatória, investigação de problemas e análise de comportamento.

---

## 7. Criação Automática de Profile

### CREATE FUNCTION handle_new_user

Automatiza a criação de um perfil quando um novo usuário se registra no sistema de autenticação do Supabase. A função extrai informações do metadata do usuário (nome completo e telefone) e cria um registro correspondente na tabela profiles. Esta automação garante que todo usuário autenticado tenha um perfil, eliminando a necessidade de sincronização manual entre as tabelas auth.users e profiles.

### CREATE TRIGGER on_auth_user_created

Conecta a função handle_new_user ao evento de criação de usuários na tabela auth.users do Supabase. Executando AFTER INSERT, garante que o usuário já existe no sistema de autenticação antes de criar o perfil. Esta integração transparente simplifica o processo de registro e mantém as tabelas sempre sincronizadas.

---

## 8. Row Level Security (RLS)

### ALTER TABLE ... ENABLE ROW LEVEL SECURITY

Ativa o Row Level Security em todas as tabelas do sistema. RLS é um recurso poderoso do PostgreSQL que permite definir políticas de acesso no nível do banco de dados, garantindo que usuários só possam ver e modificar dados aos quais têm permissão. Quando RLS está ativo, nenhuma operação é permitida por padrão - todas as permissões devem ser explicitamente concedidas através de políticas. Esta abordagem "deny by default" é fundamental para a segurança do sistema.

---

## 9. Políticas de Segurança

### Políticas para Profiles

As políticas da tabela profiles implementam um modelo de segurança onde usuários podem ver e editar apenas seu próprio perfil, enquanto administradores têm acesso total. A política "Users can update own profile" garante que usuários não possam se auto-promover a admin. A separação entre visualização e edição permite granularidade no controle de acesso, essencial para privacidade e segurança dos dados pessoais.

### Políticas para Products, Categories e Carriers

Implementam um modelo onde todos podem visualizar itens ativos (produtos, categorias e transportadoras ativas), mas apenas administradores podem gerenciar estes dados. Esta abordagem permite que o catálogo seja público para navegação e compra, enquanto mantém o controle administrativo sobre mudanças. A verificação de is_active nas políticas de SELECT permite "soft delete" transparente.

### Políticas para Addresses

Permitem que usuários gerenciem completamente seus próprios endereços (criar, visualizar, editar, deletar), com administradores tendo acesso total para suporte. Esta autonomia é essencial para a experiência do usuário, permitindo que gerenciem múltiplos endereços de entrega sem intervenção administrativa.

### Políticas para Orders

Implementam regras complexas onde usuários podem ver todos os seus pedidos, criar novos pedidos, mas só podem editar pedidos que ainda estão em status 'Cart'. Administradores têm controle total, incluindo exclusão. Esta granularidade previne alterações em pedidos já processados enquanto permite flexibilidade durante a fase de carrinho de compras.

### Políticas para Order Items

Otimizadas para performance usando EXISTS em vez de JOINs, permitem que usuários vejam itens de seus pedidos e modifiquem apenas itens em pedidos com status 'Cart'. A verificação dupla (no USING e WITH CHECK) garante segurança tanto na leitura quanto na escrita. Esta abordagem mantém a integridade dos pedidos após serem finalizados.

### Políticas para Order Statuses

Implementam o controle fino do fluxo de pedidos. Usuários podem ver status de seus pedidos, adicionar status 'Ordered' (fechar carrinho) e 'Paid' (confirmar pagamento), mas apenas seguindo as regras de transição válidas. A integração com process_order_stock na política de fechamento garante que pedidos só sejam confirmados se houver estoque disponível. Administradores podem gerenciar todos os status, mas também respeitando as transições válidas.

### Políticas para Audit Log

Restringem visualização dos logs de auditoria apenas a administradores, enquanto permitem que o sistema insira novos registros livremente. Esta configuração garante que o log de auditoria funcione transparentemente para todos os usuários, mas apenas administradores possam investigar o histórico de mudanças.

---

## 10. Storage Buckets

### INSERT INTO storage.buckets (avatars)

Cria um bucket público para armazenamento de fotos de perfil dos usuários. A configuração pública permite que as imagens sejam acessadas diretamente por URL, ideal para avatares que não contêm informações sensíveis. A integração com o Supabase Storage fornece upload direto, redimensionamento automático e CDN para distribuição eficiente das imagens.

### INSERT INTO storage.buckets (products)

Estabelece um bucket público para imagens de produtos. Similar ao bucket de avatares, a natureza pública facilita a exibição de produtos no catálogo, compartilhamento em redes sociais e indexação por motores de busca. O ON CONFLICT DO NOTHING previne erros se o bucket já existir, tornando o script idempotente.

### Políticas de Storage para Avatares

Implementam um modelo onde qualquer pessoa pode visualizar avatares (essencial para exibição em comentários, reviews, etc.), mas apenas o próprio usuário pode fazer upload, atualizar ou deletar sua foto. A verificação usa o UUID do usuário como nome da pasta, garantindo isolamento entre usuários. Esta abordagem previne que usuários modifiquem avatares de outros enquanto mantém as imagens publicamente acessíveis.

### Políticas de Storage para Produtos

Restringem o gerenciamento de imagens de produtos apenas a administradores, enquanto mantêm visualização pública. Esta configuração garante controle sobre o catálogo de produtos enquanto permite que as imagens sejam facilmente acessadas por clientes, sistemas de cache e motores de busca. A granularidade das políticas (INSERT, UPDATE, DELETE separados) permite ajuste fino de permissões se necessário.

---

## 11. Índices para Performance

### CREATE INDEX idx_profiles_is_admin

Índice parcial que indexa apenas profiles onde is_admin é true. Como administradores são minoria, este índice pequeno e eficiente acelera drasticamente a função user_is_admin(), que é chamada frequentemente pelas políticas de segurança. Índices parciais são uma otimização poderosa do PostgreSQL para conjuntos de dados com distribuição desigual.

### CREATE INDEX idx_orders_customer_id e idx_orders_customer_created

Otimizam as consultas mais comuns em orders: buscar pedidos de um cliente específico e ordená-los por data. O índice composto (customer_id, created_at DESC) é especialmente eficiente para paginação de histórico de pedidos, uma operação frequente em e-commerce. A ordenação DESC no índice corresponde à ordenação típica (pedidos mais recentes primeiro).

### CREATE INDEX idx_order_statuses_latest

Índice crucial para a performance da função get_latest_order_status(). Como esta função é chamada constantemente para verificar o estado atual de pedidos, o índice composto com ordenação descendente por datetime torna a operação praticamente instantânea. Este é um exemplo de índice desenhado especificamente para uma query crítica do sistema.

### CREATE INDEX idx_products_category_active e idx_products_active_created

Otimizam as operações mais comuns no catálogo: listar produtos ativos de uma categoria e listar produtos ativos ordenados por novidade. Estes índices compostos aceleram significativamente a navegação do catálogo e páginas de categoria, melhorando a experiência do usuário em operações de alta frequência.

### CREATE UNIQUE INDEX idx_products_unique_active_title

Índice único parcial que garante que não existam dois produtos ativos com o mesmo título. Esta constraint de negócio permite que produtos sejam "desativados" (is_active = false) sem conflito de nomes, útil para produtos sazonais ou descontinuados que podem voltar futuramente. É um exemplo elegante de como índices podem implementar regras de negócio complexas.

### Outros índices de foreign keys e campos de busca

Os demais índices otimizam joins (através de foreign keys), buscas por campos específicos (email, CEP) e operações de auditoria (user_id, timestamp). Cada índice foi cuidadosamente escolhido baseado nos padrões de acesso esperados, balanceando performance de leitura com overhead de escrita. A estratégia geral favorece leituras rápidas, apropriada para um e-commerce onde consultas superam escritas.

---

## 12. Inserção de Dados Iniciais

### INSERT INTO categories ('Geral')

Cria uma categoria padrão necessária para o funcionamento do sistema, já que products.category_id tem default 1. O ON CONFLICT DO NOTHING torna a operação idempotente, permitindo que o script seja executado múltiplas vezes sem erro. Esta categoria genérica garante que produtos possam ser criados imediatamente, mesmo antes de uma taxonomia completa ser definida.

### INSERT INTO carriers ('Transportadora Padrão')

Estabelece uma transportadora padrão para início das operações. Similar à categoria, permite que o sistema funcione imediatamente enquanto integrações reais com transportadoras são configuradas. O padrão facilita testes e desenvolvimento, além de servir como fallback para situações excepcionais.

---

## 13. Views Úteis

### CREATE VIEW orders_with_status

View materializada que combina informações de pedidos com seu status atual, dados do cliente e transportadora. Esta view elimina a necessidade de joins complexos repetidos na aplicação, centralizando a lógica de obtenção de status atual através da função get_latest_order_status(). É especialmente útil para dashboards administrativos e listagens de pedidos.

### CREATE VIEW order_items_detailed

Enriquece os itens de pedido com informações completas do produto e categoria. Esta view é fundamental para exibição de detalhes de pedidos, emails de confirmação e relatórios, eliminando múltiplos joins na aplicação. A inclusão do customer_id facilita verificações de segurança e filtros por usuário.

### CREATE VIEW cart_items

View especializada que filtra apenas itens em pedidos com status 'Cart', otimizando a operação mais frequente do e-commerce: visualizar e gerenciar o carrinho de compras. Construída sobre order_items_detailed, herda todas as informações enriquecidas while adding o filtro de status, simplificando drasticamente as queries do carrinho.

---

## 14. Funções Utilitárias

### CREATE FUNCTION get_user_cart

Função de conveniência que retorna o carrinho do usuário atual em formato otimizado para a aplicação. Usa SECURITY DEFINER para acessar dados com permissões elevadas, mas filtra apenas pelo usuário autenticado (auth.uid()), garantindo segurança. O formato tabular retornado é ideal para consumo direto pela aplicação, eliminando processamento adicional.

### CREATE FUNCTION add_to_cart

Implementa a lógica completa de adição de produtos ao carrinho, incluindo validações (usuário autenticado, produto ativo), criação automática de carrinho se necessário, e atualização de quantidade se o produto já estiver no carrinho. O retorno em JSONB com status de sucesso/erro facilita o tratamento pela aplicação. Esta função encapsula toda a complexidade da operação, garantindo consistência e segurança.

### CREATE FUNCTION close_order

Gerencia o processo crítico de fechamento de pedido (transição de 'Cart' para 'Ordered'). A função valida permissões, verifica o status atual, atualiza informações de entrega e tenta processar o estoque. O tratamento de exceções com BEGIN/EXCEPTION garante que falhas no processamento de estoque (produto sem estoque) sejam capturadas e retornadas gracefully. Esta robustez é essencial para uma boa experiência do usuário em situações de concorrência.

### CREATE FUNCTION pay_order

Processa a confirmação de pagamento, transitando pedidos de 'Ordered' para 'Paid'. Similar a close_order, implementa validações completas de segurança e estado. A separação entre fechamento e pagamento permite flexibilidade para diferentes formas de pagamento e integrações com gateways. A simplicidade da função reflete que a complexidade real do pagamento acontece em sistemas externos.

### CREATE FUNCTION set_admin_status

Fornece uma interface segura para gerenciamento de privilégios administrativos. Apenas administradores podem chamar esta função com sucesso, e todas as mudanças são automaticamente auditadas. O retorno estruturado em JSONB mantém consistência com outras funções utilitárias, facilitando o tratamento uniforme de respostas pela aplicação.