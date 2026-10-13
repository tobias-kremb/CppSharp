using System.Collections.Generic;
using System.Text;

namespace CppSharp.AST
{
    public class Event : DeclarationContext, ITypedDecl
    {
        public override T Visit<T>(IDeclVisitor<T> visitor)
        {
            return visitor.VisitEvent(this);
        }

        public Type Type => QualifiedType.Type;
        public QualifiedType QualifiedType { get; set; }

        public List<Parameter> Parameters { get; } = new List<Parameter>();

        public Declaration OriginalDeclaration { get; set; }

        public int GlobalId { get; set; }

        public string GetNameForConnect()
        {
            var nameBuilder = new StringBuilder();
            Declaration declarationContext = Namespace;
            while (!(declarationContext is TranslationUnit))
            {
                nameBuilder.Insert(0, $"{declarationContext.OriginalName}_");
                declarationContext = declarationContext.Namespace;
            }
            nameBuilder.Append(OriginalName);
            for (int i = 0; i < nameBuilder.Length; i++)
                if (!char.IsLetterOrDigit(nameBuilder[i]) && nameBuilder[i] != '_')
                    nameBuilder[i] = '_';
            return nameBuilder.ToString();
        }
    }
}
