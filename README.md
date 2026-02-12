# h2o-python-scoring-pipeline-docker-base

Container Docker para deploy simplificado de [Python Scoring Pipelines](https://docs.h2o.ai/driverless-ai/1-10-lts/docs/userguide/scoring-standalone-python.html) do H2O Driverless AI.

**Versão do Driverless AI:** 1.10 LTS

## Problema

Cada scoring pipeline exportada pelo Driverless AI vem como um `.zip` com centenas de dependências Python que precisam ser instaladas antes de rodar o modelo. Esse processo de instalação leva vários minutos e precisa ser repetido para cada novo modelo — mesmo que as dependências sejam idênticas entre pipelines.

## Solução

Esta imagem Docker **pré-instala todas as dependências compartilhadas** durante o build. Na hora de rodar um modelo novo, apenas o `.whl` específico do modelo (um pacote pequeno) precisa ser instalado. Isso reduz o tempo de startup de minutos para segundos.

### Como funciona

```
┌─────────────────────────────────────────────────┐
│  docker build (uma vez)                         │
│                                                 │
│  scoring-pipeline/  ──► install_dependencies.sh │
│  (pipeline de referência)                       │
│                                                 │
│  Instala: requirements.txt, .whl de deps,       │
│  tensorflow, xgboost, lightgbm, pyarrow,        │
│  tornado (HTTP server), thrift (TCP server)     │
│                                                 │
│  NÃO instala: scoring_h2oai_experiment_*.whl    │
└─────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────┐
│  docker run (para cada modelo)                  │
│                                                 │
│  novo-pipeline.zip ──► load_pipeline.sh         │
│                                                 │
│  Extrai o zip, instala APENAS o                 │
│  scoring_h2oai_experiment_*.whl                 │
│  e inicia o servidor HTTP de scoring            │
└─────────────────────────────────────────────────┘
```

## Pré-requisitos

- Docker
- Uma **scoring pipeline** exportada do Driverless AI (arquivo `.zip`)
- Uma **chave de licença** válida do Driverless AI

## Build da imagem

O diretório `scoring-pipeline/` **não está incluso neste repositório** — ele contém arquivos grandes e proprietários que vêm do Driverless AI. Antes do primeiro build, você precisa fornecer uma scoring pipeline de referência para que as dependências compartilhadas sejam instaladas na imagem.

**Qualquer modelo serve** como referência. As dependências são idênticas entre todas as pipelines exportadas pela mesma versão do DAI. O modelo em si não é instalado nessa etapa.

### Preparar a pipeline de referência

1. Exporte qualquer experimento do Driverless AI como **Python Scoring Pipeline**
2. Extraia o `.zip` no diretório `scoring-pipeline/`:

```bash
unzip /caminho/para/scorer.zip -d scoring-pipeline/
```

3. Verifique que os arquivos ficaram diretamente dentro de `scoring-pipeline/` (e não em um subdiretório):

```
scoring-pipeline/
├── requirements.txt
├── req_constraints_deps.txt
├── scoring_h2oai_experiment_*.whl
├── http_server.py
├── ...
```

### Construir a imagem

```bash
docker build -t h2o-python-scoring-pipeline-docker-base .
```

> **Nota:** O conteúdo de `scoring-pipeline/` é usado apenas para instalar as dependências compartilhadas durante o build. Ele é removido da imagem final e não precisa ser versionado.

## Uso

### Iniciar o servidor de scoring

```bash
docker run -p 9090:9090 \
    -e DRIVERLESS_AI_LICENSE_KEY="<sua-chave-em-base64>" \
    -v /caminho/para/pipeline.zip:/scoring/pipeline.zip \
    h2o-python-scoring-pipeline-docker-base
```

O servidor HTTP estará disponível em `http://localhost:9090`.

### Variáveis de ambiente

| Variável | Descrição |
|---|---|
| `DRIVERLESS_AI_LICENSE_KEY` | Chave de licença do DAI (string em Base64) |
| `DRIVERLESS_AI_LICENSE_FILE` | Caminho para o arquivo de licença (alternativa à chave) |
| `SCORING_PORT` | Porta do servidor HTTP (padrão: `9090`) |

### Exemplo: scoring via HTTP

Depois que o container estiver rodando, envie requisições JSON-RPC:

```bash
curl http://localhost:9090/rpc \
    --header "Content-Type: application/json" \
    --data '{
        "id": 1,
        "method": "score",
        "params": {
            "row": {
                "coluna1": 1.0,
                "coluna2": 2.0
            }
        }
    }'
```

Os nomes das colunas e tipos dependem do modelo treinado. Consulte o `example.py` dentro do `.zip` da sua pipeline para ver os campos esperados.

### Trocar de modelo

Para fazer deploy de um modelo diferente, basta iniciar um novo container apontando para outro `.zip`:

```bash
docker run -p 9090:9090 \
    -e DRIVERLESS_AI_LICENSE_KEY="<sua-chave>" \
    -v /caminho/para/outro-modelo.zip:/scoring/pipeline.zip \
    h2o-python-scoring-pipeline-docker-base
```

## Estrutura dos arquivos

| Arquivo | Descrição |
|---|---|
| `Dockerfile` | Imagem baseada em RHEL 8 (UBI) com Python 3.8 e dependências de sistema |
| `install_dependencies.sh` | Executado durante o build. Instala todas as dependências compartilhadas no virtualenv |
| `load_pipeline.sh` | Executado no startup do container. Extrai o `.zip` e instala apenas o `.whl` do modelo |
| `entrypoint.sh` | Entrypoint do container. Coordena o carregamento da pipeline e inicia o servidor HTTP |
| `scoring-pipeline/` | Pipeline de referência (não versionada — veja [Build da imagem](#build-da-imagem)) |

## Observações

- Esta imagem é configurada para deploy **sem GPU** (CPU only). O TensorFlow instalado é a versão CPU.
- A imagem base é a `registry.access.redhat.com/ubi8/ubi` (Red Hat Universal Base Image 8), que não requer subscription para uso.
- O startup do container não requer acesso à internet — todas as dependências já estão na imagem.
- Todas as scoring pipelines exportadas pela **mesma versão** do Driverless AI compartilham as mesmas dependências. Se você atualizar o DAI, reconstrua a imagem com uma pipeline de referência da nova versão.
