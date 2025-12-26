use libc::{c_char, c_int, size_t};
use std::ffi::{CStr, CString};
use std::ptr;
use std::sync::{Mutex, OnceLock};

use tokenizers::tokenizer::Tokenizer;

#[repr(C)]
pub struct HfTokenizerHandle {
    tok: Tokenizer,
}

// -------------------- 全局错误字符串（线程安全） --------------------
static LAST_ERROR: OnceLock<Mutex<Option<CString>>> = OnceLock::new();

fn err_store() -> &'static Mutex<Option<CString>> {
    LAST_ERROR.get_or_init(|| Mutex::new(None))
}

fn set_last_error(msg: impl Into<String>) {
    let s = msg.into();
    let c = CString::new(s).unwrap_or_else(|_| CString::new("error").unwrap());
    let mut g = err_store().lock().unwrap();
    *g = Some(c);
}

#[unsafe(no_mangle)]
pub extern "C" fn hf_last_error_message() -> *const c_char {
    let g = err_store().lock().unwrap();
    match &*g {
        Some(s) => s.as_ptr(),
        None => ptr::null(),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn hf_clear_last_error() {
    let mut g = err_store().lock().unwrap();
    *g = None;
}

// -------------------- 通用释放 --------------------
#[unsafe(no_mangle)]
pub extern "C" fn hf_free_ptr(p: *mut libc::c_void) {
    if !p.is_null() {
        unsafe { libc::free(p) };
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn hf_string_free(s: *mut c_char) {
    if !s.is_null() {
        unsafe { drop(CString::from_raw(s)) };
    }
}

// -------------------- 1) 加载 tokenizer.json --------------------
#[unsafe(no_mangle)]
pub extern "C" fn hf_tok_load_from_file(path: *const c_char) -> *mut HfTokenizerHandle {
    if path.is_null() {
        set_last_error("path is null");
        return ptr::null_mut();
    }
    let cstr = unsafe { CStr::from_ptr(path) };
    let path = match cstr.to_str() {
        Ok(s) => s,
        Err(e) => {
            set_last_error(format!("path utf8 error: {e}"));
            return ptr::null_mut();
        }
    };

    match Tokenizer::from_file(path) {
        Ok(tok) => Box::into_raw(Box::new(HfTokenizerHandle { tok })),
        Err(e) => {
            set_last_error(format!("Tokenizer::from_file failed: {e}"));
            ptr::null_mut()
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn hf_tok_free(h: *mut HfTokenizerHandle) {
    if !h.is_null() {
        unsafe { drop(Box::from_raw(h)) };
    }
}

// -------------------- 2) encode：字符串 -> token ids --------------------
#[unsafe(no_mangle)]
pub extern "C" fn hf_tok_encode(
    h: *mut HfTokenizerHandle,
    text: *const c_char,
    add_special_tokens: c_int,
    out_ids: *mut *mut u32,
    out_len: *mut size_t,
) -> c_int {
    if h.is_null() || text.is_null() || out_ids.is_null() || out_len.is_null() {
        set_last_error("null arg");
        return -1;
    }

    let text = unsafe { CStr::from_ptr(text) }.to_string_lossy().to_string();
    let add_special = add_special_tokens != 0;

    let tok = unsafe { &(*h).tok };

    match tok.encode(text, add_special) {
        Ok(enc) => {
            let ids = enc.get_ids();
            let n = ids.len();

            unsafe {
                let bytes = n * std::mem::size_of::<u32>();
                let p = libc::malloc(bytes) as *mut u32;
                if p.is_null() {
                    set_last_error("malloc failed");
                    return -2;
                }
                ptr::copy_nonoverlapping(ids.as_ptr(), p, n);
                *out_ids = p;
                *out_len = n as size_t;
            }
            0
        }
        Err(e) => {
            set_last_error(format!("encode failed: {e}"));
            -3
        }
    }
}

// -------------------- 3) decode：ids -> string；支持单 id --------------------
#[unsafe(no_mangle)]
pub extern "C" fn hf_tok_decode(
    h: *mut HfTokenizerHandle,
    ids: *const u32,
    len: size_t,
    skip_special_tokens: c_int,
    out_str: *mut *mut c_char,
) -> c_int {
    if h.is_null() || ids.is_null() || out_str.is_null() {
        set_last_error("null arg");
        return -1;
    }

    let tok = unsafe { &(*h).tok };
    let slice = unsafe { std::slice::from_raw_parts(ids, len as usize) };
    let skip = skip_special_tokens != 0;

    match tok.decode(slice, skip) {
        Ok(s) => {
            let c = match CString::new(s) {
                Ok(v) => v,
                Err(e) => {
                    set_last_error(format!("CString failed: {e}"));
                    return -2;
                }
            };
            unsafe { *out_str = c.into_raw(); }
            0
        }
        Err(e) => {
            set_last_error(format!("decode failed: {e}"));
            -3
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn hf_tok_decode_id(
    h: *mut HfTokenizerHandle,
    id: u32,
    skip_special_tokens: c_int,
    out_str: *mut *mut c_char,
) -> c_int {
    hf_tok_decode(h, &id as *const u32, 1 as size_t, skip_special_tokens, out_str)
}

// -------------------- 4) 查询 special token & stop token（能力） --------------------
// stop token：本库提供 token<->id 查询能力，你上层把“哪些 token 是 stop”作为策略传入即可

#[unsafe(no_mangle)]
pub extern "C" fn hf_tok_token_to_id(
    h: *mut HfTokenizerHandle,
    token: *const c_char,
    out_id: *mut u32,
    out_found: *mut c_int,
) -> c_int {
    if h.is_null() || token.is_null() || out_id.is_null() || out_found.is_null() {
        set_last_error("null arg");
        return -1;
    }

    let tok = unsafe { &(*h).tok };
    let token = unsafe { CStr::from_ptr(token) }.to_string_lossy().to_string();

    match tok.token_to_id(&token) {
        Some(id) => unsafe {
            *out_id = id;
            *out_found = 1;
            0
        },
        None => unsafe {
            *out_found = 0;
            0
        },
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn hf_tok_id_to_token(
    h: *mut HfTokenizerHandle,
    id: u32,
    out_str: *mut *mut c_char,
    out_found: *mut c_int,
) -> c_int {
    if h.is_null() || out_str.is_null() || out_found.is_null() {
        set_last_error("null arg");
        return -1;
    }

    let tok = unsafe { &(*h).tok };
    match tok.id_to_token(id) {
        Some(s) => {
            let c = match CString::new(s) {
                Ok(v) => v,
                Err(e) => {
                    set_last_error(format!("CString failed: {e}"));
                    return -2;
                }
            };
            unsafe {
                *out_str = c.into_raw();
                *out_found = 1;
            }
            0
        }
        None => unsafe {
            *out_found = 0;
            *out_str = ptr::null_mut();
            0
        },
    }
}

// 枚举 special tokens：从 added_tokens_decoder 中筛 special=true
#[unsafe(no_mangle)]
pub extern "C" fn hf_tok_list_special_tokens(
    h: *mut HfTokenizerHandle,
    out_tokens: *mut *mut *mut c_char,
    out_len: *mut size_t,
) -> c_int {
    if h.is_null() || out_tokens.is_null() || out_len.is_null() {
        set_last_error("null arg");
        return -1;
    }

    let tok = unsafe { &(*h).tok };
    let dec = tok.get_added_tokens_decoder();

    let mut specials: Vec<String> = dec
        .values()
        .filter(|t| t.special)
        .map(|t| t.content.clone())
        .collect();

    specials.sort();
    specials.dedup();

    unsafe {
        let n = specials.len();
        let arr = libc::malloc(n * std::mem::size_of::<*mut c_char>()) as *mut *mut c_char;
        if arr.is_null() {
            set_last_error("malloc failed");
            return -2;
        }

        for (i, s) in specials.into_iter().enumerate() {
            let cs = CString::new(s).unwrap();
            *arr.add(i) = cs.into_raw();
        }

        *out_tokens = arr;
        *out_len = n as size_t;
    }
    0
}

#[unsafe(no_mangle)]
pub extern "C" fn hf_tok_free_string_array(arr: *mut *mut c_char, len: size_t) {
    if arr.is_null() {
        return;
    }
    unsafe {
        for i in 0..(len as usize) {
            let p = *arr.add(i);
            if !p.is_null() {
                drop(CString::from_raw(p));
            }
        }
        libc::free(arr as *mut libc::c_void);
    }
}
