import { transformAsync } from '@babel/core'

const REQUIRED_PROPS = [
  'data-instantiation-file',
  'data-instantiation-line',
  'data-instantiation-index'
]

export default function componentPropPlugin() {
  return {
    name: 'vite-plugin-babel-props',
    enforce: 'pre',
    async transform(code, id) {
      if (!id.endsWith('.tsx')) return null

      let changed = false

      const plugin = ({ types: t }) => {
        const ensureJsxAttribute = (openingPath, name, identifier) => {
          const hasAttr = openingPath
            .get('attributes')
            .some(
              (attr) =>
                attr.isJSXAttribute() &&
                attr.get('name').isJSXIdentifier({ name })
            )

          if (hasAttr) return

          openingPath.pushContainer(
            'attributes',
            t.jsxAttribute(
              t.jsxIdentifier(name),
              t.jsxExpressionContainer(t.identifier(identifier))
            )
          )
          changed = true
        }

        const ensureDestructureInBody = (bodyPath, sourceName) => {
          if (!bodyPath?.isBlockStatement() || !sourceName) return

          const alreadyDefined = bodyPath.node.body.some((stmt) => {
            if (!t.isVariableDeclaration(stmt)) return false
            return stmt.declarations.some((decl) => {
              if (!t.isVariableDeclarator(decl)) return false
              if (!t.isObjectPattern(decl.id)) return false
              return decl.id.properties.some(
                (prop) =>
                  t.isObjectProperty(prop) &&
                  (t.isIdentifier(prop.key, { name: 'data-instantiation-file' }) ||
                   t.isStringLiteral(prop.key, { value: 'data-instantiation-file' }))
              )
            })
          })

          if (alreadyDefined) return

          const propMap = {
            'data-instantiation-file': 'dataInstantiationFile',
            'data-instantiation-line': 'dataInstantiationLine',
            'data-instantiation-index': 'dataInstantiationIndex'
          }

          const pattern = t.objectPattern(
            REQUIRED_PROPS.map((name) =>
              t.objectProperty(
                t.stringLiteral(name),
                t.identifier(propMap[name]),
                false,
                false
              )
            )
          )

          const declaration = t.variableDeclaration('const', [
            t.variableDeclarator(pattern, t.identifier(sourceName))
          ])

          bodyPath.node.body.unshift(declaration)
          changed = true
        }

        const ensureReturnAttributes = (fnPath) => {
          fnPath.traverse({
            ReturnStatement(returnPath) {
              const argument = returnPath.get('argument')
              if (!argument?.node) return

              let jsxOpeningPath = null
              argument.traverse({
                JSXOpeningElement(jsxPath) {
                  if (jsxOpeningPath) return
                  jsxOpeningPath = jsxPath
                  jsxPath.stop()
                }
              })

              if (!jsxOpeningPath) return

              ensureJsxAttribute(
                jsxOpeningPath,
                'data-instantiation-file',
                'dataInstantiationFile'
              )
              ensureJsxAttribute(
                jsxOpeningPath,
                'data-instantiation-line',
                'dataInstantiationLine'
              )
              ensureJsxAttribute(
                jsxOpeningPath,
                'data-instantiation-index',
                'dataInstantiationIndex'
              )
            }
          })
        }

        return {
          visitor: {
            VariableDeclarator(path) {
              const initPath = path.get('init')
              if (!initPath.isArrowFunctionExpression()) return

              // Only transform React components: must be PascalCase AND top-level definition
              const idNode = path.get('id')
              if (!idNode.isIdentifier()) return
              const varName = idNode.node.name
              // React components start with uppercase
              if (varName[0] !== varName[0].toUpperCase()) return
              // Must be a top-level definition (parent is VariableDeclaration, grandparent is Program)
              const declarationPath = path.parentPath
              if (!declarationPath?.parentPath?.isProgram()) return

              const fnPath = initPath
              const params = fnPath.get('params')
              const firstParam = params[0]

              if (firstParam) {
                if (firstParam.isObjectPattern()) {
                  const propMap = {
                    'data-instantiation-file': 'dataInstantiationFile',
                    'data-instantiation-line': 'dataInstantiationLine',
                    'data-instantiation-index': 'dataInstantiationIndex'
                  }

                  const existing = new Set(
                    firstParam.node.properties
                      .filter(
                        (prop) =>
                          t.isObjectProperty(prop) &&
                          (t.isIdentifier(prop.key) || t.isStringLiteral(prop.key))
                      )
                      .map((prop) =>
                        t.isIdentifier(prop.key) ? prop.key.name : prop.key.value
                      )
                  )

                  const missing = REQUIRED_PROPS.filter(
                    (prop) => !existing.has(prop)
                  ).map((name) =>
                    t.objectProperty(
                      t.stringLiteral(name),
                      t.identifier(propMap[name]),
                      false,
                      false
                    )
                  )

                  if (missing.length > 0) {
                    const restIndex = firstParam.node.properties.findIndex(
                      (prop) => t.isRestElement(prop)
                    )

                    if (restIndex === -1) {
                      firstParam.node.properties.push(...missing)
                    } else {
                      firstParam.node.properties = [
                        ...firstParam.node.properties.slice(0, restIndex),
                        ...missing,
                        ...firstParam.node.properties.slice(restIndex)
                      ]
                    }
                    changed = true
                  }
                } else if (firstParam.isIdentifier()) {
                  ensureDestructureInBody(fnPath.get('body'), firstParam.node.name)
                }
              } else {
                fnPath.node.params.unshift(t.identifier('props'))
                changed = true
                ensureDestructureInBody(fnPath.get('body'), 'props')
              }

              ensureReturnAttributes(fnPath)
            }
          }
        }
      }

      const result = await transformAsync(code, {
        filename: id,
        babelrc: false,
        configFile: false,
        sourceMaps: false,
        ast: false,
        retainLines: true,
        parserOpts: {
          sourceType: 'module',
          plugins: ['typescript', 'jsx']
        },
        plugins: [plugin]
      })

      if (!changed || !result?.code) {
        return null
      }

      return { code: result.code, map: result.map ?? null }
    }
  }
}
