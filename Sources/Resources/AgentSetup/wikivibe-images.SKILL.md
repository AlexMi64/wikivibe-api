---
name: wikivibe-images
description: Generate or edit a raster image on this machine. Use for any picture, illustration, logo, mockup, texture or diagram artwork request.
---

# Image generation on this machine

The only image generator here is the MCP tool
`mcp__wikivibe_imagegen__generate_image`. The built-in `image_gen` tool is not
available with the configured model provider, and a native
`image_generation_call` returns no file path, so the client cannot show it.
Never rely on either one.

## Procedure

1. Call `mcp__wikivibe_imagegen__generate_image` with a detailed `prompt`
   (subject, style, lighting, composition). Do not ask a clarifying question for
   a simple request.
2. The result already renders the picture in the chat, so do not call
   `view_image` and do not call any other image tool.
3. Reply in one short sentence. Never answer "готово" without a returned image.

## Pitfalls

- Answering "готово" without calling the tool is a failure: the user sees no
  picture.
- Never invent a path. If the tool errors, report the error text.
