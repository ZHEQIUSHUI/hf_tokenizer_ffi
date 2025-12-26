#pragma once
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct HfTokenizerHandle HfTokenizerHandle;

// 错误信息：返回内部静态指针（下一次调用失败后可能被覆盖）
// 建议：出错后立即读取并拷贝
const char* hf_last_error_message(void);
void hf_clear_last_error(void);

// 1) 加载 hf tokenizer（tokenizer.json）
HfTokenizerHandle* hf_tok_load_from_file(const char* path);
void hf_tok_free(HfTokenizerHandle* h);

// 2) encode
// out_ids 由库 malloc 分配，调用方用 hf_free_ptr 释放
int hf_tok_encode(HfTokenizerHandle* h,
                  const char* text,
                  int add_special_tokens,
                  uint32_t** out_ids,
                  size_t* out_len);

// 3) decode
// out_str 由库分配，调用方用 hf_string_free 释放
int hf_tok_decode(HfTokenizerHandle* h,
                  const uint32_t* ids,
                  size_t len,
                  int skip_special_tokens,
                  char** out_str);

int hf_tok_decode_id(HfTokenizerHandle* h,
                     uint32_t id,
                     int skip_special_tokens,
                     char** out_str);

void hf_string_free(char* s);
void hf_free_ptr(void* p);

// 4) token/id 查询（用于 special/stop token 查询）
int hf_tok_token_to_id(HfTokenizerHandle* h,
                       const char* token,
                       uint32_t* out_id,
                       int* out_found);

int hf_tok_id_to_token(HfTokenizerHandle* h,
                       uint32_t id,
                       char** out_str,
                       int* out_found);

// special tokens 列表（返回 token 字符串数组）
// out_tokens 是 char**（每个 char* 也由库分配）
// 释放用 hf_tok_free_string_array
int hf_tok_list_special_tokens(HfTokenizerHandle* h,
                               char*** out_tokens,
                               size_t* out_len);

void hf_tok_free_string_array(char** arr, size_t len);

#ifdef __cplusplus
}
#endif
