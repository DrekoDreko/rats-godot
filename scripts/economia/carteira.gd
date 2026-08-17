extends Node
## A carteira do jogador: o dinheiro da caçada e a conta de quantos bichos já
## foram entregues.
##
## É o único autoload do projeto, e é de propósito: o dinheiro é a única coisa do
## jogo que precisa atravessar uma troca de cena — o mapa recomeça, o que se
## ganhou nele não. Todo o resto se resolve por sinal e por grupo.
##
## Quem credita é sempre o rato, quando a caçada dele se encerra (ver
## `_pagar_recompensa` em `rato.gd`). O preço sai daqui: espécie vezes o desconto
## da morte. O HUD, quando existir, só precisa escutar `dinheiro_mudou`.

## O total mudou. `ganho` é o que acabou de entrar.
signal dinheiro_mudou(total: int, ganho: int)
## Um bicho foi fechado, com tudo o que se sabe dele. Serve para o aviso na tela
## ("+R$ 10, estrangulamento") e para o resumo de fim de turno.
signal captura_registrada(especie: EspecieRato, tipo_morte: Morte.Tipo, valor: int)

var dinheiro := 0
var capturas := 0

# Enquanto não há HUD, é este aviso no terminal que mostra o dinheiro entrando.
# Sai quando o placar chegar na tela.
const AVISAR_NO_TERMINAL := true

## Um rato foi entregue. Devolve quanto ele pagou.
func receber(especie: EspecieRato, tipo_morte: Morte.Tipo, tamanho := 1.0) -> int:
	if especie == null:
		return 0
	var valor := especie.valor(tipo_morte, tamanho)
	dinheiro += valor
	capturas += 1
	if AVISAR_NO_TERMINAL:
		print("+R$ %d por %s (%s) — total R$ %d" % [
			valor, especie.nome, Morte.nome(tipo_morte), dinheiro,
		])
	captura_registrada.emit(especie, tipo_morte, valor)
	dinheiro_mudou.emit(dinheiro, valor)
	return valor

## Zera tudo: começo de turno, e o começo de cada bancada de teste.
func zerar() -> void:
	dinheiro = 0
	capturas = 0
	dinheiro_mudou.emit(0, 0)
