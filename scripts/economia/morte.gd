class_name Morte
extends RefCounted
## Os jeitos de um rato morrer, e o quanto cada um estraga a mercadoria.
##
## Quem compra rato morto quer o bicho inteiro. Esganado ele chega sem um furo e
## sem um osso fora do lugar, e é por isso que as mãos pagam cheio: toda arma
## daqui para frente vai tirar um naco desse preço. Estrangular é o trabalho
## lento — e é o que rende.
##
## Esta classe é só uma tabela: nunca se instancia nada dela.

## De que morreu. Hoje o jogo só alcança `ESTRANGULAMENTO`, que é o que as mãos
## fazem; os outros já estão aqui à espera das armas que faltam.
enum Tipo {
	INDEFINIDA,      ## Morreu sem que arma nenhuma assumisse: queda, sumiço, sabe-se lá.
	ESTRANGULAMENTO, ## As mãos. Corpo inteiro, pelagem sem marca.
	VENENO,          ## Inteiro por fora; a carne é que não presta mais.
	ARMADILHA,       ## Morreu sozinho e ficou lá, machucado do que o prendeu.
	PERFURACAO,      ## Faca, lança, virote: um furo só, mas é um furo.
	TIRO,            ## Chumbo espalhado, pelagem rasgada.
	ESMAGAMENTO,     ## Martelo, pá, bota. O que sobra mal dá para reconhecer.
}

## Quanto do valor do bicho sobra depois de cada morte. O estrangulamento é o
## teto: nenhuma morte paga mais do que o rato inteiro vale.
const MULTIPLICADOR := {
	Tipo.ESTRANGULAMENTO: 1.00,
	Tipo.VENENO: 0.85,
	Tipo.ARMADILHA: 0.75,
	Tipo.PERFURACAO: 0.65,
	Tipo.INDEFINIDA: 0.50,
	Tipo.TIRO: 0.50,
	Tipo.ESMAGAMENTO: 0.40,
}

## Como cada morte se chama na tela e nos testes.
const NOME := {
	Tipo.INDEFINIDA: "morte natural",
	Tipo.ESTRANGULAMENTO: "estrangulamento",
	Tipo.VENENO: "veneno",
	Tipo.ARMADILHA: "armadilha",
	Tipo.PERFURACAO: "perfuração",
	Tipo.TIRO: "tiro",
	Tipo.ESMAGAMENTO: "esmagamento",
}

## Quanto do preço sobra depois desta morte, de 0 a 1.
static func multiplicador(tipo: Tipo) -> float:
	return MULTIPLICADOR.get(tipo, MULTIPLICADOR[Tipo.INDEFINIDA])

static func nome(tipo: Tipo) -> String:
	return NOME.get(tipo, NOME[Tipo.INDEFINIDA])
