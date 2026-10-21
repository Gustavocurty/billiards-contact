# Relatório: contato com raio e EDO na mira

A mesa usa um único modelo. A bola fantasma está em `c0 + s d(θ)` e encosta na bola i quando `|c0 + s d − ci| = ri + r0`. Com raios iguais isso é o círculo de raio 2R (36, se R = 18). A raiz é a entrada, `s = −b − sqrt(b² − c)`, com `b = w·d`, `c = |w|² − (2R)²` e `w = c0 − ci`. O X desenhado é esse centro, não um ponto da superfície.

Na mira, com as bolas paradas, `s` segue

```text
ds/dθ = −s (w·d′) / (w·d),   d′ = (−sin θ, cos θ),   w = c0 + s d − ci
```

Euler e RK4 integram um passo `Δθ` por frame. A força bruta volta a cada K frames. Se `|w·d|` fica abaixo de 10⁻³, ou se o resíduo `||w| − 2R|` passa de 2, o passo é jogado fora e a busca completa roda na hora. K = 1 é força bruta em todo frame.

A tacada não usa passo fixo de posição. Dentro do frame o simulador avança até o próximo evento: colisão entre bolas (menor raiz `t ≥ 0` da quadrática, e só se `Δp·Δv < 0`), parede com margem R, ou parada pelo atrito. No choque de massas iguais, a componente ao longo de `n = (cj − ci)/|cj − ci|` é trocada. O atrito constante continua entre os eventos.

A página e os testes rodam essas contas em Julia. O mesmo núcleo, com `std::chrono`, está em `cpp/benchmark.cpp` e foi compilado com MSVC `/O2` para `cpp/billiards_bench.exe`. Os números abaixo saem desse executável: 40 frames medidos, 8 de aquecimento descartados, 5 repetições, giro de 0,01 rad por frame. O tempo não inclui a segunda busca, que só serve de referência.

## Validação

A referência é a força bruta. Com K = 1 o erro médio no CSV é 0 em todos os N.

Convergência, alvo em (220, 24), raio 18, intervalo total 0,04 rad, sem recálculo no meio:

| método | erro em Δθ = 0,002 | erro em Δθ = 0,001 | ordem |
| --- | --- | --- | --- |
| Euler | 0,0783 | 0,0390 | 1,01 |
| RK4 | 1,09×10⁻⁸ | 6,78×10⁻¹⁰ | 4,01 |

Os testes também cobrem giro de passo variável, bolas aleatórias, duas bolas quase alinhadas que trocam de alvo com a mira ainda na EDO, mira tangente (a derivada vira NaN e a força bruta assume), conservação de momento e de energia cinética num choque sem atrito, reflexão na parede e o atrito que já existia.

## Escalabilidade

Tempo médio da força bruta por frame, em microssegundos. De N = 100 até N = 10⁵ o custo acompanha N: mil vezes mais bolas, cerca de 870 vezes mais tempo.

| N | raio | força bruta (µs) | mediana (µs) | p99 (µs) | FPS |
| --- | --- | --- | --- | --- | --- |
| 10 | 18 | 0,111 | 0,100 | 0,200 | 9,0×10⁶ |
| 100 | 5,69 | 0,860 | 0,800 | 0,900 | 1,2×10⁶ |
| 1 000 | 1,80 | 7,32 | 7,30 | 8,00 | 1,4×10⁵ |
| 10 000 | 0,569 | 72,6 | 72,0 | 86,3 | 1,4×10⁴ |
| 100 000 | 0,180 | 746 | 726 | 1 140 | 1,3×10³ |

O raio encolhe com `18 √(10/N)` para a fração de área não explodir. O relógio do Windows anda de 100 ns: em N = 10 a média está nesse piso e não separa os métodos.

## Erro × tempo

K = 30, cinco repetições. O gráfico `benchmark_pareto.svg` põe log do tempo médio contra log do erro médio; Euler em vermelho, RK4 em azul. K = 1 fica com erro 0 e por isso não entra como ponto útil da fronteira.

| N | bruta (µs) | Euler (µs) | RK4 (µs) | erro médio RK4 | bola errada RK4 |
| --- | --- | --- | --- | --- | --- |
| 10 | 0,115 | 0,084 | 0,096 | 0,021 | 0% |
| 100 | 0,811 | 0,404 | 0,205 | 25,2 | 28% |
| 1 000 | 10,1 | 2,06 | 2,08 | 14,0 | 35% |
| 10 000 | 72,8 | 30,8 | 34,4 | 5,76 | 35% |
| 100 000 | 749 | 401 | 513 | 1,86 | 30% |

Em N = 10 e K = 5, ainda sem troca de alvo, o erro médio do Euler é 0,44 e o do RK4 é 0,0042. A ordem vista na tabela de convergência aparece aqui também. Em N = 10 e K = 60 os dois sobem para erro ~9,7 e 5% de bola errada: o giro saiu do cone da bola e o rastreamento segurou o alvo antigo.

## O que não favorece a EDO

Para N pequeno a força bruta ganha. Em N = 10 o tempo dos dois cabe no mesmo quantum de 100 ns, e a força bruta tem erro zero. Não há ganho de tempo que pague trocar o método.

A EDO fica mais barata na média só quando K > 1 e a varredura é grande, porque a maior parte dos frames não olha as N bolas. Em N = 10⁵ e K = 30, RK4 baixa a média de 749 µs para 513 µs. O p99 continua em 0,86 ms, perto da varredura completa: o frame em que K estoura, ou em que a mira encosta na tangência, paga o custo cheio.

Esse atalho perde o alvo. No giro constante de 0,01 rad, bolas vizinhas entram na frente da reta e a bola rastreada chega perto da tangência. Até o próximo recálculo o X fica na bola antiga. Por isso a taxa de bola errada fica em torno de 30% para N ≥ 100, em qualquer K > 1 desta grade. A invalidação por tangência existe e dispara a força bruta, mas ela chega depois que o índice já divergiu. K = 1 evita isso e, nesse caso, custa o mesmo que a força bruta.
