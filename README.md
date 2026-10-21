# Mesa de sinuca — contato por força bruta e EDO

Aplicação didática para comparar a localização do primeiro contato da bola branca por **força bruta** e por **rastreamento via EDO** (Euler/RK4). A mesa preserva atrito, reflexão nas bordas e colisões elásticas tratadas por eventos; o foco da comparação é o centro da bola fantasma.

> Execute o app e faça uma captura da mesa e outra da aba **Resultados** para inserir nos slides/entrega. Os gráficos podem ser baixados em PNG diretamente pela interface.

## Modelo matemático

Se `c0` é o centro da branca, `ci` o centro da bola `i`, `d(θ) = (cos θ, sin θ)` e `s` a distância na rota, o contato da bola fantasma satisfaz

```text
|c0 + s d(θ) − ci| = r0 + ri                 (2R quando os raios são iguais)
```

Com `w = c0 + s d − ci`, a interseção reta × círculo vem da quadrática. A menor raiz não negativa é o primeiro contato. Para rastrear a raiz enquanto o taco gira, deriva-se implicitamente:

```text
ds*/dθ = −s (w · d′) / (w · d),    d′ = (−sin θ, cos θ)
```

Euler usa um estágio; RK4 usa quatro estágios. A cada `K` frames a busca por força bruta corrige o rastreador (`K = 1` equivale a força bruta contínua). Quando `w · d` é pequeno (quase tangência), o resíduo do círculo é alto ou a solução deixa de ser válida, há correção imediata. A referência por força bruta é sempre calculada **fora** do tempo medido do método.

## Algoritmos

```text
força_bruta(bolas, θ):
  para cada bola diferente da branca: resolva reta × círculo de raio r0 + ri
  retorne a raiz s >= 0 menor

rastrear(θ, s, alvo, Δθ):
  s <- Euler ou RK4 da EDO
  se s/resíduo/tangência forem inválidos: retorne força_bruta
  retorne c0 + s d(θ)

híbrido(frame):
  se K = 1 ou frame múltiplo de K: força_bruta
  senão: rastrear
  calcule força_bruta novamente apenas como referência de erro
```

## Compilação e execução

Requisitos: Julia **1.10+**, compilador C++17 opcional (`g++`) e navegador moderno.

```powershell
julia --project=. -e "using Pkg; Pkg.instantiate()"
julia --project=. -e "using Pkg; Pkg.test()"
julia --project=. app/app.jl
```

Abra `http://127.0.0.1:8000`. Para o benchmark C++ de escala (até `10^5` bolas, com raio reduzido para manter baixa cobertura da mesa):

```powershell
g++ -O3 -std=c++17 -o cpp/billiards_bench.exe cpp/benchmark.cpp
.\cpp\billiards_bench.exe benchmark_results.csv benchmark_pareto.svg
```

O botão **Rodar experimentos** usa esse executável quando disponível; caso contrário, mede uma varredura reproduzível em Julia. A aba Resultados também aceita `benchmark_results.csv`.

## Como usar

- Arraste qualquer ponto da mesa para girar o taco em tempo real. Use `←`/`→` para ajuste de `0,5°`.
- Pegue o taco (`grab`) e puxe para trás. A barra mostra a força; solte acima do limiar para tacar. Não existe botão de tacada.
- Durante o movimento o taco some e reaparece na última direção quando todas as bolas param.
- A linha branca tracejada é a rota. **X amarelo** é o método escolhido; **losango ciano** é a referência exata. Um segmento vermelho e `Δ` aparecem acima de `0,5`; duas bolas destacadas indicam troca de alvo.
- Use **Pausar/Continuar**, **Resetar**, **Sortear posições** e os cenários Aglomerado, Quase alinhadas e Quase tangente na aba Simulação.

## Validação e medições

O tempo do algoritmo é a média de várias execuções do cálculo de contato, em µs; o FPS mostrado é medido com `requestAnimationFrame`. Erro, erro máximo e taxa de bola errada usam sempre a referência por força bruta, sem contaminarem essa medição. A validação física sem atrito verifica conservação de momento linear e energia cinética nas colisões elásticas.

A aba **Resultados** produz: tempo por frame × `N` em log-log; Pareto erro × tempo por `K`; erro médio/máximo e bola errada × `K`; convergência erro × passo `Δθ` (Euler ~1, RK4 ~4); tabela de validação física, tabela-resumo e conclusão exportável.

O resultado negativo faz parte da análise: para `N` pequeno, o custo da EDO pode superar a força bruta. O rastreamento passa a compensar em escalas maiores e com `K` moderado; quase tangência e troca de bola permanecem limitações importantes e motivam os recálculos.

## Limitações e próximos passos

O modelo é 2D, sem efeito, caçapas ou perda de energia na borda. Trabalhos futuros incluem detectar troca de alvo antes do próximo `K`, adaptação automática de passo perto de tangências e uma bateria maior de cenários físicos.
