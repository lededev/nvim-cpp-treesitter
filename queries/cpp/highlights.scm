; inherits: c

; 基于 tree-sitter-cpp v0.23.4 queries/highlights.scm (MIT, (c) 2014 Max Brunsfeld) 重排。
; 目的：三档语义层级 —— 执行流最亮 > 运算符/小标点显眼 > 类型与修饰词退到背景。

;==================== 继承上游的函数/类型/字面量部分 ====================
(call_expression
  function: (qualified_identifier
    name: (identifier) @function))

(template_function
  name: (identifier) @function)

(template_method
  name: (field_identifier) @function)

(function_declarator
  declarator: (qualified_identifier
    name: (identifier) @function))

(function_declarator
  declarator: (field_identifier) @function)

((namespace_identifier) @type
  (#match? @type "^[A-Z]"))

(auto) @type

(this) @variable.builtin
(null "nullptr" @constant)

(module_name
  (identifier) @module)

(raw_string_literal) @string

;==================== 第 1 档：执行流关键词（最突出）====================
"return" @keyword.return
"co_return" @keyword.return

[
  "co_await"
  "co_yield"
] @keyword.coroutine

[
  "throw"
  "try"
  "catch"
] @keyword.exception

;==================== 第 2 档：运算符与小标点（显眼）====================
[
  "<=>"
  "->*"
] @operator

[
  "and"
  "or"
  "not"
  "bitand"
  "bitor"
  "xor"
  "not_eq"
  "and_eq"
  "or_eq"
  "xor_eq"
  "compl"
] @keyword.operator

; new/delete 是"用英文单词书写的运算符"，归运算符而非泛化 keyword
[
  "new"
  "delete"
] @keyword.operator

; 模板尖括号是结构而非比较运算：从 @operator 提升到 @punctuation.bracket
(template_parameter_list
  [
    "<"
    ">"
  ] @punctuation.bracket)

(template_argument_list
  [
    "<"
    ">"
  ] @punctuation.bracket)

;==================== 第 3 档：语法关键词（收敛到背景）====================
[
  "class"
  "namespace"
  "template"
  "typename"
  "using"
  "concept"
  "requires"
  "friend"
] @keyword.type

[
  "constexpr"
  "consteval"
  "constinit"
  "mutable"
  "explicit"
  "virtual"
  "noexcept"
  "override"
  "final"
  "inline"
  "public"
  "private"
  "protected"
] @keyword.modifier

[
  "import"
  "export"
  "module"
] @keyword.import

"operator" @keyword

; 属性整体显眼（对齐你参考截图里的 [[nodiscard]]）
; [[ ]] 是 attribute_declaration 的直接子节点，attribute 节点不含括号
(attribute_declaration) @attribute.builtin
