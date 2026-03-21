namespace Addons.DialogueManagerTypeChecker;

using System;
using System.Linq;
using System.Reflection;
using Godot;
using Godot.Collections;

public partial class TypeChecker : RefCounted {
    public Dictionary? GetCsScriptMethodInfo(Script script, string methodName) {
        string typeName = script.ResourcePath.GetFile().GetBaseName();
        var type = Assembly.GetExecutingAssembly().GetTypes().FirstOrDefault(t => t.Name == typeName);

        if (type == null)
            return null;
        var methodInfo = type.GetMethods(
                BindingFlags.Instance | BindingFlags.Static | BindingFlags.Public | BindingFlags.DeclaredOnly
            )
            .FirstOrDefault(m => m.Name == methodName && !m.IsSpecialName);
        if (methodInfo == null)
            return null;

        return BuildMethodDictionary(methodInfo);
    }

    // Helper
    private Dictionary BuildMethodDictionary(MethodInfo methodInfo) {
        var args = new Array<Dictionary>();
        foreach (var param in methodInfo.GetParameters()) {
            args.Add(
                new Dictionary() {
                    { "name", param.Name ?? "" },
                    { "type", (int)Variant.Type.Nil },
                    { "class_name", GetFriendlyTypeName(param.ParameterType) },
                }
            );
        }
        return new Dictionary() {
            { "name", methodInfo.Name },
            { "type", "method" },
            { "args", args },
        };
    }

    private static string GetFriendlyTypeName(Type type) {
        if (type == typeof(int))
            return "int";
        if (type == typeof(long))
            return "long";
        if (type == typeof(float))
            return "float";
        if (type == typeof(double))
            return "double";
        if (type == typeof(bool))
            return "bool";
        if (type == typeof(string))
            return "string";
        if (type == typeof(void))
            return "void";
        if (type == typeof(byte))
            return "byte";
        if (type == typeof(short))
            return "short";
        if (type == typeof(char))
            return "char";
        if (type == typeof(decimal))
            return "decimal";
        return type.Name;
    }
}
