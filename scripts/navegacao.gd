extends NavigationRegion3D
## Malha de navegação por onde os ratos andam.
##
## O cenário é montado à mão no `mundo.tscn`, então em vez de guardar a malha
## pronta dentro do arquivo da cena — onde ela envelheceria a cada obstáculo que
## muda de lugar — ela é assada aqui, quando o mapa abre, a partir dos corpos
## estáticos do grupo `cenario`.
##
## Os números da malha (no `mundo.tscn`) são medidas de rato: raio 0.25, um
## pouco mais que o corpo dele, que é o que sobra de folga entre o caminho e a
## parede; altura 0.75, para ele não achar que passa por baixo de coisa nenhuma;
## e degrau máximo de 0.25, que separa a rampa da plataforma. O tamanho da célula
## fica no padrão do projeto de propósito: malha e mapa precisam combinar.

func _ready() -> void:
	# Sem thread: assar este mapa custa poucos milissegundos e garante que os
	# ratos já encontrem a malha pronta na primeira volta da física.
	bake_navigation_mesh(false)
