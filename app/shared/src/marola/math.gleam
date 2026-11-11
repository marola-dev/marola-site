//// gleam_stdlib has no trigonometry. These bind the platform's math library;
//// they are the only target-specific code in this package.

pub const pi = 3.141592653589793

@external(erlang, "math", "sin")
@external(javascript, "./math_ffi.mjs", "sin")
pub fn sin(x: Float) -> Float

@external(erlang, "math", "cos")
@external(javascript, "./math_ffi.mjs", "cos")
pub fn cos(x: Float) -> Float

@external(erlang, "math", "atan")
@external(javascript, "./math_ffi.mjs", "atan")
pub fn atan(x: Float) -> Float

@external(erlang, "math", "asin")
@external(javascript, "./math_ffi.mjs", "asin")
pub fn asin(x: Float) -> Float

@external(erlang, "math", "exp")
@external(javascript, "./math_ffi.mjs", "exp")
pub fn exp(x: Float) -> Float

@external(erlang, "math", "log")
@external(javascript, "./math_ffi.mjs", "log")
pub fn ln(x: Float) -> Float
