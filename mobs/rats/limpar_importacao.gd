@tool
extends EditorScenePostImport
## Limpeza do `Rat_Fbx.fbx` na importação.
##
## O FBX foi exportado com a cena inteira do Blender: junto com o rato vieram a
## luz e a câmera do autor, e todas as animações têm faixas apontando para esses
## dois nós. Sem esta limpeza cada rato do mapa carregaria uma luz própria e o
## AnimationPlayer reclamaria das faixas órfãs toda vez que um rato nascesse.
##
## Também caem aqui as animações duplicadas: o exportador gera uma cópia de cada
## ação para cada objeto da cena (`Camera|Run`, `Light|Attack`,
## `Rat Model|Death`), e só as do prefixo `Rat|` interessam.

const NOS_DESCARTAVEIS := ["Light", "Camera"]
const PREFIXO_DAS_ANIMACOES := "Rat|"
## As duas animações que o rato repete sem parar; as outras são de uma vez só.
const ANIMACOES_EM_CICLO := ["Rat|Idle", "Rat|Run"]

func _post_import(cena: Node) -> Object:
	for nome in NOS_DESCARTAVEIS:
		var no := cena.find_child(nome, false, false)
		if no != null:
			no.free()

	var animador := cena.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if animador == null:
		return cena

	for nome_biblioteca in animador.get_animation_library_list():
		var biblioteca := animador.get_animation_library(nome_biblioteca)
		for nome_animacao in biblioteca.get_animation_list():
			if not nome_animacao.begins_with(PREFIXO_DAS_ANIMACOES):
				biblioteca.remove_animation(nome_animacao)
				continue
			var animacao := biblioteca.get_animation(nome_animacao)
			_limpar_faixas(animacao)
			if nome_animacao in ANIMACOES_EM_CICLO:
				animacao.loop_mode = Animation.LOOP_LINEAR
	return cena

## Tira da animação as faixas dos nós que acabaram de ser removidos.
func _limpar_faixas(animacao: Animation) -> void:
	for i in range(animacao.get_track_count() - 1, -1, -1):
		if animacao.track_get_path(i).get_name(0) in NOS_DESCARTAVEIS:
			animacao.remove_track(i)
