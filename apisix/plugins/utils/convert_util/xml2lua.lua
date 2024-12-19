--- @module Module providing a non-validating XML stream parser in Lua
--
--  Features:
--  =========
--
--      * Tokenises well-formed XML (relatively robustly)
--      * Flexible handler based event API (see below)
--      * Parses all XML Infoset elements - ie.
--          - Tags
--          - Text
--          - Comments
--          - CDATA
--          - XML Decl
--          - Processing Instructions
--          - DOCTYPE declarations
--      * Provides limited well-formedness checking
--        (checks for basic syntax & balanced tags only)
--      * Flexible whitespace handling (selectable)
--      * Entity Handling (selectable)
--
--  Limitations:
--  ============
--
--      * Non-validating
--      * No charset handling
--      * No namespace support
--      * Shallow well-formedness checking only (fails
--        to detect most semantic errors)
--
--  API:
--  ====
--
--  The parser provides a partially object-oriented API with
--  functionality split into tokeniser and handler components.
--
--  The handler instance is passed to the tokeniser and receives
--  callbacks for each XML element processed (if a suitable handler
--  function is defined). The API is conceptually similar to the
--  SAX API but implemented differently.
--
--  XML data is passed to the parser instance through the 'parse'
--  method (Note: must be passed a single string currently)
--
--  License:
--  ========
--
--      This code is freely distributable under the terms of the [MIT license](LICENSE).
--
--
--@author Paul Chakravarti (paulc@passtheaardvark.com)
--@author Manoel Campos da Silva Filho
local xml2lua = {}

local string = string
local pairs = pairs
local type = type
local table = table
local tostring = tostring

---Gets an _attr element from a table that represents the attributes of an XML tag,
--and generates a XML String representing the attibutes to be inserted
--into the openning tag of the XML
--
--@param attrTable table from where the _attr field will be got
--@return a XML String representation of the tag attributes
local function attrToXml(attrTable)
  local s = ""
  local attrTable = attrTable or {}

  for k, v in pairs(attrTable) do
      s = s .. " " .. k .. "=" .. '"' .. v .. '"'
  end
  return s
end

---Gets the first key of a given table
local function getFirstKey(tb)
    local ret = nil
   if type(tb) == "table" then
      for k, v in pairs(tb) do
        ret = k
      end
      return ret
   end

   return tb
end

---Converts a Lua table to a XML String representation.
--@param tb Table to be converted to XML
--@param tableName Name of the table variable given to this function,
--                 to be used as the root tag.
--@param level Only used internally, when the function is called recursively to print indentation
--
--@return a String representing the table content in XML
function xml2lua.toXml(tb, tableName, level)
  local level = level or 1
  local firstLevel = level
  local spaces = string.rep(' ', level*2)
  local xmltb = level == 1 and {'<'..tableName..'>'} or {}

  for k, v in pairs(tb) do
      if type(v) == "table" then
         --If the keys of the table are a number, it represents an array
         if type(k) == "number" then
            local attrs = attrToXml(v._attr)
            v._attr = nil
            table.insert(xmltb,
                spaces..'<'..tableName..attrs..'>\n'..xml2lua.toXml(v, tableName, level+1)..
                '\n'..spaces..'</'..tableName..'>')
         else
            level = level + 1
            if type(getFirstKey(v)) == "number" then
               table.insert(xmltb, xml2lua.toXml(v, k, level))
            else
               local attrs = attrToXml(v._attr)
               v._attr = nil
               if next(v) ~= nil then
                --  print("k=1221", k, ",v=", v)
                 table.insert(xmltb,
                   spaces..'<'..k..attrs..'>\n'.. xml2lua.toXml(v, k, level+1)..
                     '\n'..spaces..'</'..k..'>')
               else
                 table.insert(xmltb, spaces..'<'..k..attrs..'>'..'</'..k..'>')
               end
            end
         end
      else
          if type(k) == "number" then
            table.insert(xmltb, spaces..'<'..tableName..'>'..tostring(v)..'</'..tableName..'>')
          else
            table.insert(xmltb, spaces..'<'..k..'>'..tostring(v)..'</'..k..'>')
          end
      end
  end

  if firstLevel == 1 then
     table.insert(xmltb, '</'..tableName..'>\n')
  end
  return table.concat(xmltb, "\n")
end

return xml2lua
