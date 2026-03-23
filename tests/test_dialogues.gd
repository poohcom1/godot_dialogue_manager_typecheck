extends GdUnitTestSuite

const TypeChecker := preload("res://addons/dialogue_manager_type_check/type_checker/type_checker.gd")

var _type_checker: TypeChecker

func before() -> void:
	_type_checker = TypeChecker.new()

func after() -> void:
	_type_checker.cleanup()

func test_valid():
	var dialogue: DialogueResource = load("res://tests/resources/valid.dialogue")
	var results := await _type_checker.check_type(dialogue)
	
	assert_dict(results).is_empty()

func test_invalid():
	var dialogue: DialogueResource = load("res://tests/resources/invalid.dialogue")
	var results := await _type_checker.check_type(dialogue)
	
	assert_int(results[5].type).is_equal(TypeChecker.TypeErrorType.UnknownMethod)
	assert_int(results[6].type).is_equal(TypeChecker.TypeErrorType.UnknownMethod)
	assert_int(results[7].type).is_equal(TypeChecker.TypeErrorType.UnknownMember)
	assert_int(results[8].type).is_equal(TypeChecker.TypeErrorType.UnknownEnum)
	assert_int(results[9].type).is_equal(TypeChecker.TypeErrorType.StaticMemberAccess)
	assert_int(results[10].type).is_equal(TypeChecker.TypeErrorType.StaticFuncAccess)
	assert_int(results[11].type).is_equal(TypeChecker.TypeErrorType.UnknownMethod)
	assert_int(results[12].type).is_equal(TypeChecker.TypeErrorType.UnknownMethod)
	
	assert_int(results[13].type).is_equal(TypeChecker.TypeErrorType.ArgsCount)
	
	assert_int(results[14].type).is_equal(TypeChecker.TypeErrorType.ArgMismatch)
	assert_str(results[14].msg).is_equal('Expected argument 1 to be of type int, got String in "test_args_typed()".')
	
	assert_int(results[15].type).is_equal(TypeChecker.TypeErrorType.ArgMismatch)
	assert_str(results[15].msg).is_equal('Expected argument 2 to be of type String, got int in "test_args_typed()".')
	
	assert_int(results[16].type).is_equal(TypeChecker.TypeErrorType.ArgMismatch)
	assert_str(results[16].msg).is_equal('Expected argument 3 to be of type Vector2, got int in "test_args_typed()".')
	
	assert_int(results[17].type).is_equal(TypeChecker.TypeErrorType.UnknownMethod)
	assert_int(results[19].type).is_equal(TypeChecker.TypeErrorType.SubcriptInvalidIndex)
	assert_int(results[20].type).is_equal(TypeChecker.TypeErrorType.SubcriptInvalidIndex)
	
	
