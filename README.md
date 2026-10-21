# Contato da bola fantasma

Simulador de sinuca 2D que compara dois jeitos de descobrir **qual bola a branca atinge primeiro e onde**: uma busca completa (força bruta) e um rastreamento por equação diferencial (EDO).

![Mesa com a mira e o X de contato](docs/img/mesa.png)

*A linha tracejada é a rota da branca. O X amarelo é o contato previsto pelo método escolhido e o losango ciano é o contato exato (referência). O painel à direita mostra controles e métricas em tempo real.*

## Ideia

Trabalho da disciplina Tópicos Especiais em Linguagens de Programação. A pergunta é: dá para prever a primeira bola atingida com menos processamento que uma busca completa, mantendo um erro aceitável?

- **Força bruta (referência):** resolve a interseção da mira com todas as bolas e escolhe a mais próxima. Custo O(N) por atualização.
- **Rastreamento:** enquanto o taco gira, atualiza o ponto de contato integrando uma EDO em θ (Euler ou RK4), sem olhar as outras bolas.
- **Intervalo K:** a cada K atualizações a força bruta corrige o rastreamento. K = 1 equivale a recalcular sempre.

O contato é a posição da branca no instante do impacto (bola fantasma de raio 2R). Para a mira `P(s) = c0 + s·d(θ)`, ele é a menor raiz de `|c0 + s·d − ci|² − (2R)² = 0`, e a derivada implícita dá a EDO:

```
ds*/dθ = −s · (w·d′) / (w·d),   w = c0 + s·d − ci,   d′ = (−sin θ, cos θ)
```

A EDO atua só na **mira**, com as bolas paradas. Na tacada, o movimento usa cálculo por eventos (colisões, paredes e atrito). Perto da tangência a derivada explode, e se outra bola passar a ser a primeira atingida, o rastreamento não percebe. Nesses casos o programa chama a força bruta.

## Como rodar

Requisitos: Julia 1.13 (GenieFramework 3.1.0, PlotlyBase, StaticArrays). Testado no Windows.

```powershell
julia --project=. -e "using Pkg; Pkg.instantiate()"
julia --project=. app\app.jl          # abre http://127.0.0.1:8000
julia --project=. -e "using Pkg; Pkg.test()"   # 236 testes
```

O benchmark em C++ (`cpp/billiards_bench.exe`) gera o `benchmark_results.csv`, que não vem no clone (está no `.gitignore`). Use o botão **Rodar experimentos** da aba Resultados ou:

```powershell
.\cpp\billiards_bench.exe benchmark_results.csv tmp\bench.svg
```

## Como usar

- **Arraste** sobre a mesa para girar o taco (ou use ← →, em passos de 0,5°).
- **Puxe o taco para trás** e solte para dar a tacada.
- Escolha o **algoritmo**, o **integrador** (Euler ou RK4), o número de **bolas** (2 a 16) e o **K** (1 a 120).
- Use os cenários prontos: *Aglomerado*, *Quase alinhadas* (a primeira bola atingida muda com um giro pequeno) e *Quase tangente* (pior caso da EDO).
- Quando o método erra a bola, aparece "bola errada"; quando os contatos divergem mais de 0,5, aparece um segmento vermelho com o Δ.

## Resultados

O benchmark testou 90 configurações: N = 10, 100, 1.000, 10.000 e 100.000 bolas, K = 1, 5, 10, 30, 60 e 120, e os métodos força bruta, Euler e RK4. Giro de 0,01 rad por atualização, 40 atualizações × 5 repetições. O erro é a distância entre os centros previstos, em unidades da mesa (1000×1000). Tempos em µs, ganho = tempo da busca ÷ tempo do método.

**Resumo com K = 30:**

| N | Busca | Euler: tempo (ganho) | Euler: erro / bola errada | RK4: tempo (ganho) | RK4: erro / bola errada |
|---:|---:|---:|---:|---:|---:|
| 10 | 0,113 | 0,087 (1,30×) | 0,751 / 0% | 0,092 (1,23×) | 0,0207 / 0% |
| 100 | 0,811 | 0,254 (3,19×) | 11,94 / 20% | 0,2045 (3,97×) | 25,18 / 27,5% |
| 1.000 | 7,456 | 2,378 (3,14×) | 17,04 / 42,5% | 3,316 (2,25×) | 13,96 / 35% |
| 10.000 | 75,01 | 34,82 (2,15×) | 6,57 / 50% | 36,25 (2,07×) | 5,756 / 35% |
| 100.000 | 780,0 | 405,2 (1,93×) | 2,661 / 45% | 518,8 (1,50×) | 1,862 / 30% |

A tabela completa está em [`docs/tabela_resumo.md`](docs/tabela_resumo.md).

![Tempo por atualização contra N](docs/img/tempo_por_frame.svg)

*Tempo × N (log-log, K = 30). A busca cresce com N; o rastreamento cresce menos, mas em N = 100.000 o ganho é de apenas 1,5× a 1,9×, bem menor que K. A maior parte das atualizações ainda cai em correções antecipadas (115 e 145 buscas em 200 frames, contra 205 com K = 1).*

![Erro médio contra tempo médio](docs/img/pareto.svg)

*Erro × tempo: cada ponto é um par (N, K) do rastreamento. Quanto mais perto do canto inferior esquerdo, melhor. Pontos com erro 0 (K = 1) estão em 10⁻⁶ para caber no log.*

![N = 100](docs/img/erro_k_n100.svg)

*Erro e bola errada × K para N = 100. Com K > 1, a bola errada fica entre 20% e 35%.*

### Validação

![Convergência](docs/img/convergencia.svg)

*Erro × passo Δθ, com uma bola e sem recálculo. A ordem observada é ≈ 1,00 para Euler e ≈ 4,01 para RK4, como a teoria prevê.*

Os testes automáticos também verificam a conservação de momento e de energia cinética nas colisões (sem atrito), o atrito, a parada e o rebote na parede (`test/pool_test.jl`).

## Conclusão

- O rastreamento **reduz o tempo médio** para N ≥ 100 e K > 1, com ganho de cerca de 1,3× a 4,2×.
- O **RK4 é mais preciso que o Euler** quando a bola alvo não muda: em N = 10 e K = 5, o erro cai de 0,44 para 0,004. Mas o integrador **não escolhe o alvo**: com N ≥ 100, de 20% a 50% das amostras apontam a bola errada.
- Para N ≥ 100 e K > 1, nenhuma configuração de rastreamento teve erro médio ≤ 2 e bola errada ≤ 5%. O ganho de velocidade existe, mas custa precisão na escolha do alvo.
- K = 1 tem erro zero por construção (recalcula sempre); serve como teste de sanidade.

## Limitações

- O benchmark usa giro fixo de 0,01 rad por atualização, diferente do giro do mouse na interface.
- O erro está em unidades da mesa, sem dividir pelo raio (com N = 100.000, o raio é 0,18).
- Sem caçapas, efeito ou rotação da bola; a EDO não acompanha bolas em movimento.
- O botão *Aglomerado* usa o triângulo inicial, não uma cena própria.

## Estrutura

```
app/          interface (Genie)
src/          geometria, busca, EDO, simulação, métricas
test/         testes
cpp/          benchmark em C++
scripts/      plot_benchmark.jl, convergence.jl
docs/         figuras e tabela de resultados
```

**Autor:** Gustavo Curty · Tópicos Especiais em Linguagens de Programação
