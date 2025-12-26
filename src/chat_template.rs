use std::{ffi::CString, fs, path::{Path, PathBuf}};
use minijinja::{Environment, context};
use serde_json::Value;

use crate::{set_last_error};

fn read_json(path: &Path) -> Option<Value> {
    let s = fs::read_to_string(path).ok()?;
    serde_json::from_str::<Value>(&s).ok()
}

fn get_token_string(v: &Value) -> Option<String> {
    if v.is_string() {
        return v.as_str().map(|s| s.to_string());
    }
    if v.is_object() {
        if let Some(c) = v.get("content") {
            if c.is_string() {
                return c.as_str().map(|s| s.to_string());
            }
        }
    }
    None
}

fn find_chat_template(model_dir: &Path) -> Result<String, String> {
    // 0) 先尝试独立模板文件（更符合近期一些仓库做法）
    for fname in ["chat_template.jinja", "chat_template.jinja2"] {
        let p = model_dir.join(fname);
        if let Ok(s) = fs::read_to_string(&p) {
            if !s.trim().is_empty() {
                return Ok(s);
            }
        }
    }

    // 1) tokenizer_config.json: chat_template
    let tc_path = model_dir.join("tokenizer_config.json");
    if let Some(tc) = read_json(&tc_path) {
        if let Some(ct) = tc.get("chat_template").and_then(|x| x.as_str()) {
            if !ct.trim().is_empty() {
                return Ok(ct.to_string());
            }
        }
    }

    // 2) chat_template.json: { "chat_template": "..." }  (SmolVLM2 这类)
    let ctj_path = model_dir.join("chat_template.json");
    if let Some(j) = read_json(&ctj_path) {
        if let Some(ct) = j.get("chat_template").and_then(|x| x.as_str()) {
            if !ct.trim().is_empty() {
                return Ok(ct.to_string());
            }
        }
        // 有些人会嵌一层：{"template":{"chat_template":"..."}}，这里也顺便兜一下
        if let Some(ct) = j.pointer("/template/chat_template").and_then(|x| x.as_str()) {
            if !ct.trim().is_empty() {
                return Ok(ct.to_string());
            }
        }
    }

    Err(format!(
        "chat template not found.\n\
         tried:\n\
         - {}/chat_template.jinja(.2)\n\
         - {}/tokenizer_config.json:chat_template\n\
         - {}/chat_template.json:chat_template",
        model_dir.display(),
        model_dir.display(),
        model_dir.display(),
    ))
}


fn load_special_tokens(model_dir: &Path) -> (Option<String>, Option<String>, Option<String>, Option<String>, Option<String>, Option<String>, Option<String>) {
    // 尽量从 tokenizer_config.json / special_tokens_map.json 读常见 special
    let tc = read_json(&model_dir.join("tokenizer_config.json")).unwrap_or(Value::Null);
    let sm = read_json(&model_dir.join("special_tokens_map.json")).unwrap_or(Value::Null);

    let get = |key: &str| -> Option<String> {
        tc.get(key).and_then(get_token_string)
            .or_else(|| sm.get(key).and_then(get_token_string))
    };
    

    let bos = get("bos_token");
    let eos = get("eos_token");
    let unk = get("unk_token");
    let pad = get("pad_token");
    let sep = get("sep_token");
    let cls = get("cls_token");
    let mask = get("mask_token");
    (bos, eos, unk, pad, sep, cls, mask)
}

pub fn apply_chat_template_from_dir(
    model_dir: &Path,
    messages_json: &str,
    add_generation_prompt: bool,
) -> Result<String, String> {
    let template = find_chat_template(model_dir)?;

    // messages_json 要求是 JSON array，元素形如：
    // { "role": "user|assistant|system", "content": "..." }
    // 也允许 content 是 array（多模态结构），模板能处理就行。
    let messages: Value = serde_json::from_str(messages_json)
        .map_err(|e| format!("messages_json parse error: {}", e))?;
    if !messages.is_array() {
        return Err("messages_json must be a JSON array".to_string());
    }

    let (bos_token, eos_token, unk_token, pad_token, sep_token, cls_token, mask_token) =
        load_special_tokens(model_dir);

    let mut env = Environment::new();
    env.add_template("chat", &template)
        .map_err(|e| format!("add_template error: {}", e))?;

    let tmpl = env.get_template("chat")
        .map_err(|e| format!("get_template error: {}", e))?;

    // 传入变量名尽量对齐 HF 生态常用：
    // messages / add_generation_prompt / bos_token/eos_token/... 等
    let rendered = tmpl.render(context! {
        messages => messages,
        add_generation_prompt => add_generation_prompt,
        bos_token => bos_token,
        eos_token => eos_token,
        unk_token => unk_token,
        pad_token => pad_token,
        sep_token => sep_token,
        cls_token => cls_token,
        mask_token => mask_token,
    }).map_err(|e| format!("render error: {}", e))?;

    Ok(rendered)
}

// C ABI：给 C++ 调用
#[unsafe(no_mangle)]
pub extern "C" fn hf_chat_apply_template_from_dir(
    model_dir: *const std::ffi::c_char,
    messages_json: *const std::ffi::c_char,
    add_generation_prompt: i32,
    out_prompt: *mut *mut std::ffi::c_char,
) -> i32 {
    if model_dir.is_null() || messages_json.is_null() || out_prompt.is_null() {
        set_last_error("null pointer input");
        return -1;
    }

    let model_dir = unsafe { std::ffi::CStr::from_ptr(model_dir) }.to_string_lossy().to_string();
    let messages_json = unsafe { std::ffi::CStr::from_ptr(messages_json) }.to_string_lossy().to_string();

    let dir = PathBuf::from(model_dir);
    let add = add_generation_prompt != 0;

    match apply_chat_template_from_dir(&dir, &messages_json, add) {
        Ok(s) => {
            match CString::new(s) {
                Ok(cs) => {
                    unsafe { *out_prompt = cs.into_raw(); }
                    0
                }
                Err(_) => {
                    set_last_error("CString::new failed (string contains NUL?)");
                    -2
                }
            }
        }
        Err(e) => {
            set_last_error(&e);
            -3
        }
    }
}
