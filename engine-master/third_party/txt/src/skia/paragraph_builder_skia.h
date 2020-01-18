/*
 * Copyright 2019 Google Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#ifndef LIB_TXT_SRC_PARAGRAPH_BUILDER_SKIA_H_
#define LIB_TXT_SRC_PARAGRAPH_BUILDER_SKIA_H_

#include "txt/paragraph_builder.h"

#include "third_party/skia/modules/skparagraph/include/ParagraphBuilder.h"

namespace txt {

// Implementation of ParagraphBuilder based on Skia's text layout module.
class ParagraphBuilderSkia : public ParagraphBuilder {
 public:
  ParagraphBuilderSkia(const ParagraphStyle& style,
                       std::shared_ptr<FontCollection> font_collection);

  virtual ~ParagraphBuilderSkia();

  virtual void PushStyle(const TextStyle& style) override;
  virtual void Pop() override;
  virtual const TextStyle& PeekStyle() override;
  virtual void AddText(const std::u16string& text) override;
  virtual void AddPlaceholder(PlaceholderRun& span) override;
  virtual std::unique_ptr<Paragraph> Build() override;

 private:
  std::shared_ptr<skia::textlayout::ParagraphBuilder> builder_;
  TextStyle base_style_;
  std::stack<TextStyle> txt_style_stack_;
};

}  // namespace txt

#endif  // LIB_TXT_SRC_PARAGRAPH_BUILDER_SKIA_H_
