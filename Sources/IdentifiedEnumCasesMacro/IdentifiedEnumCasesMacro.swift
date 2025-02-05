import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import Foundation

public struct IdentifiedEnumCasesMacro: MemberMacro {
  public static func expansion<Declaration, Context>(
    of node: SwiftSyntax.AttributeSyntax,
    providingMembersOf declaration: Declaration,
    in context: Context) throws -> [SwiftSyntax.DeclSyntax] where Declaration : SwiftSyntax.DeclGroupSyntax, Context : SwiftSyntaxMacros.MacroExpansionContext {
      
      guard let declaration = declaration.as(EnumDeclSyntax.self) else {
        let enumError = Diagnostic(node: node._syntaxNode, message: Diagnostics.mustBeEnum)
        context.diagnose(enumError)
        return []
      }
      
      guard let enumCases: [SyntaxProtocol] = declaration.memberBlock
        .children(viewMode: .fixedUp).filter({ $0.kind == .memberDeclList })
        .first?
        .children(viewMode: .fixedUp).filter({ $0.kind == SyntaxKind.memberDeclListItem })
        .flatMap({ $0.children(viewMode: .fixedUp).filter({ $0.kind == .enumCaseDecl })})
        .flatMap({ $0.children(viewMode: .fixedUp).filter({ $0.kind == .enumCaseElementList })})
        .flatMap({ $0.children(viewMode: .fixedUp).filter({ $0.kind == .enumCaseElement })})
      else {
        let enumError = Diagnostic(node: node._syntaxNode, message: Diagnostics.mustHaveCases)
        context.diagnose(enumError)
        return []
      }

      let caseIds: [String] = enumCases.compactMap { enumCase in
        guard let firstToken = enumCase.firstToken(viewMode: .fixedUp) else {
          return nil
        }

        guard case let .identifier(id) = firstToken.tokenKind else {
          return nil
        }

        return id
      }
      
      guard !caseIds.isEmpty else {
        let enumError = Diagnostic(node: node._syntaxNode, message: Diagnostics.mustHaveCases)
        context.diagnose(enumError)
        return []
      }

      let modifier = declaration.hasPublicModifier ? "public " : ""
      let enumID = "\(modifier)enum CaseID: String, Hashable, Identifiable, CaseIterable, CustomStringConvertible {\n\(caseIds.map { "  case \($0)\n" }.joined())\n  \(modifier)var description: String {\nself.rawValue\n  }\n \n var id: Self { self }  }"
      let idAccessor = "\(modifier)var caseID: CaseID {\n  switch self {\n\(caseIds.map { "  case .\($0): .\($0)\n" }.joined()) }\n}"

      return [
        DeclSyntax(stringLiteral: enumID),
        DeclSyntax(stringLiteral: idAccessor)
      ]
    }
  
  public enum Diagnostics: String, DiagnosticMessage {
    
    case mustBeEnum, mustHaveCases
    
    public var message: String {
      switch self {
      case .mustBeEnum:
        return "`@IdentifiedEnumCasesMacro` can only be applied to an `enum`"
      case .mustHaveCases:
        return "`@IdentifiedEnumCasesMacro` can only be applied to an `enum` with `case` statements"
      }
    }
    
    public var diagnosticID: MessageID {
      MessageID(domain: "IdentifiedEnumCasesMacro", id: rawValue)
    }
    
    public var severity: DiagnosticSeverity { .error }
  }
}

private extension DeclGroupSyntax {
  var hasPublicModifier: Bool {
    self.modifiers.children(viewMode: .fixedUp)
      .compactMap { syntax in
        syntax.as(DeclModifierSyntax.self)?
          .children(viewMode: .fixedUp)
          .contains { syntax in
            switch syntax.as(TokenSyntax.self)?.tokenKind {
            case .keyword(.public):
              return true
            default:
              return false
            }
          }
      }
      .contains(true)
  }
}

@main
struct MacroPlugin: CompilerPlugin {
  let providingMacros: [Macro.Type] = [
    IdentifiedEnumCasesMacro.self,
  ]
}
