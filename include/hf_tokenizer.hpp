#pragma once
#include <cstdint>
#include <stdexcept>
#include <string>
#include <vector>

#include "hf_tokenizer_c.h"

class HFTokenizer {
public:
  explicit HFTokenizer(const std::string& tokenizer_json_path) {
    h_ = hf_tok_load_from_file(tokenizer_json_path.c_str());
    if (!h_) throw std::runtime_error(last_err("load_from_file"));
  }

  ~HFTokenizer() {
    if (h_) hf_tok_free(h_);
    h_ = nullptr;
  }

  HFTokenizer(const HFTokenizer&) = delete;
  HFTokenizer& operator=(const HFTokenizer&) = delete;

  HFTokenizer(HFTokenizer&& other) noexcept : h_(other.h_) { other.h_ = nullptr; }
  HFTokenizer& operator=(HFTokenizer&& other) noexcept {
    if (this != &other) {
      if (h_) hf_tok_free(h_);
      h_ = other.h_;
      other.h_ = nullptr;
    }
    return *this;
  }

  // 2) encode
  std::vector<uint32_t> encode(const std::string& text, bool add_special = true) const {
    uint32_t* ids = nullptr;
    size_t len = 0;
    int rc = hf_tok_encode(h_, text.c_str(), add_special ? 1 : 0, &ids, &len);
    if (rc != 0) throw std::runtime_error(last_err("encode"));

    std::vector<uint32_t> out(ids, ids + len);
    hf_free_ptr(ids);
    return out;
  }

  // 3) decode(ids)
  std::string decode(const std::vector<uint32_t>& ids, bool skip_special = true) const {
    char* s = nullptr;
    int rc = hf_tok_decode(h_, ids.data(), ids.size(), skip_special ? 1 : 0, &s);
    if (rc != 0) throw std::runtime_error(last_err("decode"));

    std::string out(s ? s : "");
    hf_string_free(s);
    return out;
  }

  // 3) decode(single id)
  std::string decode_id(uint32_t id, bool skip_special = true) const {
    char* s = nullptr;
    int rc = hf_tok_decode_id(h_, id, skip_special ? 1 : 0, &s);
    if (rc != 0) throw std::runtime_error(last_err("decode_id"));

    std::string out(s ? s : "");
    hf_string_free(s);
    return out;
  }

  // 4) special tokens（token 字符串列表）
  std::vector<std::string> special_tokens() const {
    char** arr = nullptr;
    size_t n = 0;
    int rc = hf_tok_list_special_tokens(h_, &arr, &n);
    if (rc != 0) throw std::runtime_error(last_err("list_special_tokens"));

    std::vector<std::string> out;
    out.reserve(n);
    for (size_t i = 0; i < n; ++i) out.emplace_back(arr[i] ? arr[i] : "");
    hf_tok_free_string_array(arr, n);
    return out;
  }

  // token -> id（可用于 stop token 查询/配置）
  bool token_to_id(const std::string& token, uint32_t& out_id) const {
    int found = 0;
    int rc = hf_tok_token_to_id(h_, token.c_str(), &out_id, &found);
    if (rc != 0) throw std::runtime_error(last_err("token_to_id"));
    return found != 0;
  }

  // stop token：给候选 token 字符串，返回能找到的 id 列表
  std::vector<uint32_t> stop_token_ids(const std::vector<std::string>& candidates) const {
    std::vector<uint32_t> out;
    for (const auto& t : candidates) {
      uint32_t id = 0;
      int found = 0;
      int rc = hf_tok_token_to_id(h_, t.c_str(), &id, &found);
      if (rc == 0 && found) out.push_back(id);
    }
    return out;
  }

private:
  HfTokenizerHandle* h_{nullptr};

  static std::string last_err(const char* where) {
    const char* e = hf_last_error_message();
    return std::string(where) + ": " + (e ? e : "unknown error");
  }
};
