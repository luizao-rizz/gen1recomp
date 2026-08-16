-- GraphicsWrapper: Global protection for all graphics operations
-- Intercepts love.graphics.setCanvas and newCanvas to handle graphics context loss
-- This wrapper catches every canvas operation without needing to modify 1000+ files

local GraphicsWrapper = {}

-- Store original functions
local originalSetCanvas = love.graphics.setCanvas
local originalNewCanvas = love.graphics.newCanvas
local originalDraw = love.graphics.draw

-- Track valid canvases
local validCanvases = setmetatable({}, { __mode = "k" })

-- Safe wrapper for setCanvas
function love.graphics.setCanvas(canvas, ...)
  -- nil is always safe (resets to screen)
  if canvas == nil then
    return originalSetCanvas(nil, ...)
  end
  
  -- Canvas must exist and be valid
  if not canvas or type(canvas) ~= "userdata" then
    -- Silently ignore invalid canvas (don't crash)
    return false
  end
  
  -- Try to use it; if it fails, continue without crashing
  local ok, err = pcall(originalSetCanvas, canvas, ...)
  if not ok then
    -- Canvas is corrupted (graphics context loss), reset to screen
    -- Log the error but don't propagate
    local Logger = require("src.core.Logger")
    Logger.warn("setCanvas failed (graphics context loss?)", tostring(err))
    pcall(originalSetCanvas, nil)
    return false
  end
  
  return true
end

-- Safe wrapper for newCanvas
function love.graphics.newCanvas(...)
  local ok, canvas = pcall(originalNewCanvas, ...)
  if ok and canvas then
    validCanvases[canvas] = true
    return canvas
  end
  -- Canvas creation failed (VRAM, graphics context), return nil
  local Logger = require("src.core.Logger")
  Logger.warn("newCanvas failed (graphics context or VRAM?)")
  return nil
end

-- Safe wrapper for draw operations
function love.graphics.draw(drawable, ...)
  if not drawable then return end
  
  -- Validate canvas if it's one
  if type(drawable) == "userdata" then
    local ok, err = pcall(originalDraw, drawable, ...)
    if not ok then
      local Logger = require("src.core.Logger")
      Logger.warn("graphics.draw failed", tostring(err))
      return false
    end
  else
    -- Non-canvas drawable (image, etc) - just try it
    pcall(originalDraw, drawable, ...)
  end
  
  return true
end

-- Expose original for emergency access
GraphicsWrapper.originalSetCanvas = originalSetCanvas
GraphicsWrapper.originalNewCanvas = originalNewCanvas
GraphicsWrapper.originalDraw = originalDraw

return GraphicsWrapper
