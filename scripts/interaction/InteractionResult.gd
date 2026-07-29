class_name InteractionResult
extends RefCounted
## InteractionResolver 가 돌려주는 판정 결과.
##
## 별도 파일로 둔 이유: 내부 클래스로 두면 enum 스코프가 헷갈리고,
## Main/DebugPanel 이 결과 종류를 참조할 때 경로가 길어진다.

enum Kind {
	SUCCESS,            ## 룰이 걸렸고 전제조건도 충족
	PRECONDITION_FAIL,  ## 룰은 있으나 아직 이르다 → 그 룰 고유의 실패 대사
	DEFAULT_LINE,       ## 핫스폿/아이템/동사 기본 대사
}

const KIND_NAMES := ["SUCCESS", "PRECOND_FAIL", "DEFAULT"]

var kind: int = Kind.DEFAULT_LINE
var rule_id: String = ""
var result: Dictionary = {}      ## ResultRunner 가 실행할 op 묶음
var debug_note: String = ""


func is_success() -> bool:
	return kind == Kind.SUCCESS


func kind_name() -> String:
	return str(KIND_NAMES[clampi(kind, 0, KIND_NAMES.size() - 1)])
