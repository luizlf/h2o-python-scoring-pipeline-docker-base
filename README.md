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

### Build em ambiente corporativo (proxy / SSL interception)

O build precisa de acesso à rede para baixar pacotes RPM (Red Hat/EPEL) e Python (PyPI, PyTorch). Em ambientes corporativos com proxy e/ou SSL interception, use os build args abaixo.

#### Proxy HTTP/HTTPS

```bash
docker build \
    --build-arg HTTP_PROXY=http://proxy.empresa.com:8080 \
    --build-arg HTTPS_PROXY=http://proxy.empresa.com:8080 \
    --build-arg NO_PROXY=localhost,127.0.0.1,.empresa.com \
    -t h2o-python-scoring-pipeline-docker-base .
```

#### SSL interception (certificado CA customizado)

Se o proxy corporativo faz SSL interception, coloque o(s) certificado(s) CA (`.crt` ou `.pem`) no diretório `certs/` antes do build:

```bash
cp /caminho/para/ca-corporativo.crt certs/
docker build -t h2o-python-scoring-pipeline-docker-base .
```

Os certificados são instalados automaticamente no trust store do sistema (`/etc/pki/ca-trust/`) antes de qualquer download. O diretório `certs/` é ignorado pelo git.

#### Mirrors internos (Artifactory, Nexus, etc.)

Para usar repositórios internos em vez dos públicos:

```bash
docker build \
    --build-arg PIP_INDEX_URL=https://artifactory.empresa.com/api/pypi/pypi-remote/simple \
    --build-arg PIP_TRUSTED_HOST=artifactory.empresa.com \
    --build-arg PYTORCH_WHEEL_URL=https://artifactory.empresa.com/pytorch-wheels/torch_stable.html \
    --build-arg EPEL_RPM_URL=https://mirror.empresa.com/epel/epel-release-latest-8.noarch.rpm \
    -t h2o-python-scoring-pipeline-docker-base .
```

#### Build args disponíveis

| Build arg | Descrição | Padrão |
|---|---|---|
| `HTTP_PROXY` | Proxy HTTP | — |
| `HTTPS_PROXY` | Proxy HTTPS | — |
| `NO_PROXY` | Hosts que não passam pelo proxy | — |
| `PIP_INDEX_URL` | URL do índice PyPI (Artifactory, Nexus, etc.) | PyPI público |
| `PIP_TRUSTED_HOST` | Host confiável para pip (desabilita verificação SSL para este host) | — |
| `PYTORCH_WHEEL_URL` | URL do índice de wheels do PyTorch | `download.pytorch.org/...` |
| `EPEL_RPM_URL` | URL do RPM do EPEL | `dl.fedoraproject.org/...` |

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

| Variável | Descrição | Padrão |
|---|---|---|
| `DRIVERLESS_AI_LICENSE_KEY` | Chave de licença do DAI (string em Base64) | — |
| `DRIVERLESS_AI_LICENSE_FILE` | Caminho para o arquivo de licença (alternativa à chave) | — |
| `SCORING_PORT` | Porta do servidor HTTP | `9090` |
| `DRIVERLESS_AI_ENABLE_H2O_RECIPES` | Habilitar servidor H2O-3 para receitas | `0` |
| `dai_enable_h2o_recipes` | Habilitar receitas H2O-3 (config interna do DAI) | `0` |
| `dai_enable_custom_recipes` | Habilitar receitas customizadas | `0` |

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
| `certs/` | Certificados CA customizados para SSL interception (não versionados) |

## Limitações

- **Sem suporte a GPU**: imagem configurada para deploy CPU-only. PyTorch e TensorFlow são as versões CPU.
- **Sem suporte a receitas H2O-3**: o servidor H2O-3 para receitas customizadas é desabilitado por padrão (requer Java, que não está instalado na imagem). Pipelines que dependem de receitas H2O-3 customizadas **não funcionarão**.
- **Pacotes removidos para redução de tamanho**: bibliotecas de visualização (plotly, bokeh, panel), GPU (cupy, h2o4gpu), H2O-3 client, tensorboard e cmake foram removidos. Se a sua pipeline depender de algum desses pacotes, será necessário ajustar o `install_dependencies.sh`.

## Otimizações de tamanho

A imagem inclui diversas otimizações para reduzir o tamanho (~8.0 GB em disco, ~1.9 GB comprimida):

- **PyTorch CPU-only**: instala `torch+cpu` em vez da versão CUDA (~2.5 GB economizados)
- **Bind mount no build**: a pipeline de referência é montada via `--mount=type=bind` durante o build, evitando que seus ~1.2 GB fiquem em uma layer do Docker
- **Remoção de pacotes GPU**: cupy-cuda, h2o4gpu, duplicatas de xgboost/lightgbm
- **Remoção de pacotes não essenciais**: bibliotecas de visualização, tensorboard, cmake, botocore, babel
- **Limpeza de .whl no runtime**: `load_pipeline.sh` remove os `.whl` de dependências após extrair a pipeline, mantendo apenas o `.whl` do modelo
- **Limpeza de cache**: pip cache e arquivos temporários são removidos no mesmo layer do build

## Observações

- A imagem base é a `registry.access.redhat.com/ubi8/ubi` (Red Hat Universal Base Image 8), que não requer subscription para uso.
- O startup do container não requer acesso à internet — todas as dependências já estão na imagem.
- Todas as scoring pipelines exportadas pela **mesma versão** do Driverless AI compartilham as mesmas dependências. Se você atualizar o DAI, reconstrua a imagem com uma pipeline de referência da nova versão.
