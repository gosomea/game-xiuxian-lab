extends RefCounted
## test_vocabulary：词汇表运行时读取端测试。
## 覆盖：索引可加载、已登记词汇可查、未登记词汇返回 false、描述可读。
##
## 这是「词汇表双向契约」的验证：Python 门禁在提交前拒绝未登记词汇，
## 本测试确认运行时读的是同一份 index.json。

static func run(t) -> void:
	_test_index_loads(t)
	_test_registered_tag_found(t)
	_test_unregistered_tag_rejected(t)
	_test_groups_and_components(t)
	_test_describe(t)


static func _test_index_loads(t) -> void:
	t.begin_case()
	Vocabulary.reload()
	var index := Vocabulary.index()
	t.assert_true(index.has("tags"), "索引应含 tags 段")
	t.assert_true(index.has("components"), "索引应含 components 段")
	t.assert_true(Vocabulary.all_tags().size() > 0, "至少应有一个已登记 tag（否则索引未生成）")


static func _test_registered_tag_found(t) -> void:
	t.begin_case()
	t.assert_true(Vocabulary.has_tag(&"regen_block"), "regen_block 已在词汇表登记，应可查到")


static func _test_unregistered_tag_rejected(t) -> void:
	t.begin_case()
	# 故意用未登记的词汇名做否定断言。这里必须用 StringName(String) 构造而非 &"" 字面量：
	# verify-vocabulary 门禁会拒绝源码中任何未登记的 &"" 字面量，包括测试文件里的。
	t.assert_false(Vocabulary.has_tag(StringName("regen_blok")), "拼写错误的 tag 不应被认为已登记")
	t.assert_false(Vocabulary.has_tag(StringName("never_registered_tag")), "未登记的 tag 应返回 false")


static func _test_groups_and_components(t) -> void:
	t.begin_case()
	t.assert_true(Vocabulary.has_group(&"actor"), "actor 组应已登记")
	t.assert_true(Vocabulary.has_component(&"VitalsComponent"), "VitalsComponent 应已登记")


static func _test_describe(t) -> void:
	t.begin_case()
	var described := Vocabulary.describe_tag(&"regen_block")
	t.assert_true(described.length() > 0, "已登记 tag 应有释义文本")
	t.assert_eq(Vocabulary.describe_tag(StringName("nope")), "(未登记)", "未登记 tag 的释义应为占位文本")
