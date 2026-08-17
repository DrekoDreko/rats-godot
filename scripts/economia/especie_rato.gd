class_name EspecieRato
extends Resource
## Uma raça de rato: como ela se chama, com que pelo ela nasce e quanto ela vale.
##
## Cada espécie é um arquivo em `recursos/especies/`. Rato novo no jogo é
## duplicar um desses e mexer nos números — nada de código.
##
## Por enquanto a espécie cuida só de aparência e preço; o que o bicho aguenta e
## a que velocidade ele corre continuam sendo do nó do rato (`rato.gd`), para não
## haver dois lugares mandando no mesmo número.

@export var nome := "Rato"
## As pelagens que ele pode sortear ao nascer. Vazio deixa o material do modelo
## como veio.
@export var pelagens: Array[Texture2D] = []

@export_group("Recompensa")
## O preço do bicho inteiro, antes do desconto da morte.
@export var valor_base := 10
## O quanto um indivíduo pode ser maior ou menor que os da mesma espécie
## (0.15 = ±15%). Em zero todos valem igual.
@export_range(0.0, 0.5) var variacao := 0.0

## Quanto este bicho, deste tamanho, vale morto deste jeito. Nunca menos de 1: um
## rato esmagado ainda é um rato entregue.
func valor(tipo_morte: Morte.Tipo, tamanho := 1.0) -> int:
	return maxi(1, roundi(valor_base * tamanho * Morte.multiplicador(tipo_morte)))

## O tamanho de um indivíduo, sorteado quando ele nasce.
func sortear_tamanho() -> float:
	if variacao <= 0.0:
		return 1.0
	return randf_range(1.0 - variacao, 1.0 + variacao)

## Uma das pelagens da espécie, ou nulo se ela não tiver nenhuma.
func sortear_pelagem() -> Texture2D:
	if pelagens.is_empty():
		return null
	return pelagens.pick_random()
