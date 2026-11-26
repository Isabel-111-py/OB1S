@tool
class_name QuestData
extends Resource

## Definición de datos para una misión del juego.
## Totalmente configurable: todos los títulos, descripciones, objetivos,
## diálogos, requisitos y botones son personalizables desde el Inspector.

@export_group("Información Básica")
## Identificador único de la misión (ej. "mision_bosque_1", "entrega_medicina").
@export var id: String = "mision_1"
## Nombre visible de la misión en el inventario y diálogos.
@export var title: String = "Nueva Misión"
## Descripción detallada de la misión y su contexto.
@export_multiline var description: String = ""
## Texto breve del objetivo actual mientras se busca o entrega al objetivo.
@export var objective_text: String = ""


@export_group("Personajes y Flujo Multi-NPC (Opcional)")
## ID del NPC que asigna la misión y entrega la recompensa final (ej. "dr_ergot").
@export var giver_npc_id: String = ""
## ID del NPC receptor o destino de la entrega (ej. "funry").
@export var target_npc_id: String = ""
## Si es verdadero, tras entregar el ítem al target_npc, el jugador debe volver con giver_npc para informar y cobrar.
@export var return_to_giver: bool = false
## Texto del objetivo mostrado en el inventario y diálogos cuando hay que regresar con el giver.
@export var return_objective_text: String = ""


@export_group("Ítem Otorgado al Aceptar (Opcional)")
## Si no está vacío, al aceptar la misión se le entrega automáticamente este ítem al inventario del jugador.
@export var grant_item_on_accept: StringName = &""
@export var grant_item_name: String = ""
@export_multiline var grant_item_desc: String = ""
@export var grant_item_icon: Texture2D


@export_group("Condición de Completado / Entrega")
## Tipo de objetivo necesario:
## - Entregar Ítem / Mejora: Requiere que el jugador tenga en su inventario 'required_item_id'.
## - Hablar con NPC: Solo requiere hablar con el NPC destino.
## - Evento / Flag: Requiere que un evento haya ocurrido (flag en QuestManager).
## - Manual / Código: Se completa llamando por script a QuestManager.deliver_quest_step() o complete_quest().
@export_enum("Entregar Ítem / Mejora", "Hablar con NPC", "Evento / Flag", "Manual / Código") var completion_type: String = "Entregar Ítem / Mejora"

## ID del ítem / mejora requerido en el inventario para la entrega (ej. "medicina").
@export var required_item_id: String = ""
## Si es verdadero, el ítem se retira del inventario al realizar la entrega al NPC objetivo.
@export var consume_item_on_complete: bool = true
## Bandera de evento requerida si completion_type es 'Evento / Flag'.
@export var completion_event_flag: String = ""


@export_group("Requisitos y Desbloqueo")
## ID de la misión previa que DEBE estar completada para que esta misión esté disponible.
@export var prerequisite_quest_id: String = ""
## Bandera o flag de evento que debe ser verdadera (ej. "boss_derrotado").
@export var required_event_flag: String = ""


@export_group("Recompensas Finales")
## ID de mejora o ítem a entregar como recompensa al completar (opcional).
@export var reward_upgrade_id: String = ""
@export var reward_upgrade_name: String = ""
@export_multiline var reward_upgrade_desc: String = ""
@export var reward_upgrade_icon: Texture2D

## Espacio de munición al que sumar flechas (0, 1 o 2). -1 para no dar flechas.
@export_range(-1, 2) var reward_ammo_slot: int = -1
## Cantidad de flechas a otorgar.
@export var reward_ammo_amount: int = 0

## Bandera de evento que se activará al completar la misión (ej. "puerta_abierta").
@export var event_flag_to_set: String = ""


@export_group("Textos y Botones Personalizados (Opcional)")
## Texto que se muestra como estado cuando la misión ha sido finalizada con éxito.
@export var status_completed_text: String = "¡Misión Completada con Éxito! ✓"
## Texto personalizado para el botón de aceptar (dejar vacío para usar el predeterminado del NPC)
@export var button_accept_text: String = ""
## Texto personalizado para el botón de entregar (dejar vacío para usar el predeterminado del NPC)
@export var button_deliver_text: String = ""
## Texto personalizado para el botón de completar (dejar vacío para usar el predeterminado del NPC)
@export var button_complete_text: String = ""
