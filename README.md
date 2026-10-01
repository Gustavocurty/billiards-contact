# Mesa de sinuca com ponto de contato

A página simula uma tacada: o taco mira a bola branca, a linha tracejada mostra a rota e as bolas começam paradas. Depois da tacada elas se movem, colidem e desaceleram. Por baixo, o projeto ainda compara a busca por força bruta com o rastreamento do ponto de contato por EDO.

## Algoritmos

**Força bruta.** Em cada frame percorre as outras bolas, descarta interseções inválidas e fica com o contato válido mais próximo. A complexidade é O(N).

**Rastreamento.** A força bruta roda no frame 0 e de novo a cada `K` frames. Nos frames intermediários o ponto `X(t)` é integrado por uma EDO, com Euler ou RK4.

```text
força bruta → EDO → EDO → ... → força bruta
```

`K` é `recalculation_interval`. Com `K = 30`, a busca completa volta a cada 30 frames. `K = 1` faz a força bruta em todos os frames.

## Decisões matemáticas

A mesa tem 1000 por 1000. O benchmark e os testes de referência usam raio desprezível e movimento uniforme, sem atrito e sem colisão entre bolas. Nesse modelo o contato é a interseção das retas

```text
C₁ + s d₁ = Cᵢ + τ dᵢ,  s ≥ 0
```

`s < 0` fica atrás da bola de taco e é descartado. `τ` não é limitado: a trajetória da outra bola é a reta da velocidade. Retas paralelas, inclusive colineares, não têm interseção única. Bola de taco parada não define trajetória.

Para movimento retilíneo uniforme a derivada do contato é identicamente nula. Diferenciando `s = (Δ × dᵢ) / (d₁ × dᵢ)` obtém-se `s' = -1` e `X' = (1 + s') d₁ = 0`: as retas não mudam enquanto a velocidade é constante. Euler e RK4 reproduzem essa solução. O erro aparece quando a velocidade muda e o ponto rastreado só é corrigido no próximo múltiplo de `K`.

O erro exibido é `E = ||X_rastreado - X_força bruta||`. Essa segunda busca é opcional e não entra no tempo do algoritmo.

Na mesa da interface as bolas têm raio, começam paradas e a rota é o raio do taco: o contato é o primeiro círculo atingido, não a interseção de duas velocidades. A tacada aplica a força na direção do ângulo. O atrito constante reduz a velocidade até parar. No choque de massas iguais, a componente normal das velocidades é trocada. A borda reflete a velocidade quando o centro chega à margem do raio. Euler e RK4 continuam no núcleo e no CSV; na tela eles não se distinguem, porque entre um evento e outro o contato previsto não se move.

## Instalação

É preciso Julia 1.10 ou mais recente.

```julia
julia --project=. -e "using Pkg; Pkg.instantiate()"
```

## Testes

```julia
julia --project=. -e "using Pkg; Pkg.test()"
```

## Interface

```julia
julia --project=. app/app.jl
```

Abra http://127.0.0.1:8000 se o navegador não abrir sozinho. A primeira execução compila o Genie e pode demorar.

O taco aponta para a bola branca. **Ângulo** gira o taco e a linha tracejada na hora. **Força** muda o comprimento do taco e a velocidade da tacada. **Tacada** dispara a bola branca se ela estiver parada. Enquanto uma bola se move, a linha tracejada segue a velocidade dela e vai encurtando com o atrito. A linha pontilhada no alvo parado mostra para onde essa bola sai depois do contato.

**Força bruta** recalcula o contato em todo frame. **Rastreamento** só corrige no intervalo `K`; nos outros frames o ponto segue a EDO. `K` não muda a tacada nem o atrito. A quantidade de bolas reconstrói a mesa ao soltar o controle. **Continuar** só retoma um movimento já iniciado. **Reset** e **Aleatório** devolvem todas as bolas paradas.

Euler, RK4 e o passo `dt` saíram da página: no modelo da rota eles não mudam o desenho. Os dois métodos e o efeito de `K` no tempo e no erro continuam no benchmark. O tempo mostrado é só o da atualização do contato. Com **Calcular erro** ligado, a força bruta extra da validação fica de fora desse tempo.

## Benchmark

```julia
julia --project=. -e "using BilliardsContact; run_benchmark()"
```

O mesmo experimento está no botão **Benchmark CSV**. O arquivo `benchmark_results.csv` sai na raiz do projeto. As colunas são número de bolas, `K`, algoritmo, método, frames, tempo médio por frame, tempo médio da força bruta, tempo médio da EDO, erro médio, erro máximo e quantidade de recálculos.

O tempo de frame não inclui a busca usada apenas para medir o erro. Para o rastreamento, menos recálculos reduzem o custo e, depois das reflexões, aumentam o erro. Euler e RK4 coincidem neste modelo porque `X' = 0` entre as reflexões; RK4 avalia a derivada em quatro estágios.
