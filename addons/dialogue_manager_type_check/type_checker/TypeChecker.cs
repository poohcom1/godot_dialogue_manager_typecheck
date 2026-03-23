namespace Addons.DialogueManagerTypeChecker;

using System;
using System.Linq;
using System.Reflection;
using Godot;
using Godot.Collections;

public partial class TypeChecker : RefCounted
{
    public Dictionary GetCsScriptMethodInfo(Script script, string methodName)
    {
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
    private static Dictionary BuildMethodDictionary(MethodInfo methodInfo)
    {
        var args = new Array<Dictionary>();
        foreach (var param in methodInfo.GetParameters())
        {
            args.Add(
                new Dictionary() {
                    { "name", param.Name ?? "" },
                    { "type", (int)GetVariantType(param.ParameterType) },
                    { "class_name", new StringName() },
                }
            );
        }
        return new Dictionary() {
            { "name", methodInfo.Name },
            { "type", "method" },
            { "args", args },
            { "return", new Dictionary() {
                { "type", (int)GetVariantType(methodInfo.ReturnType) },
                { "class_name", new StringName() }, }
            },
        };
    }

    private static Variant.Type GetVariantType(Type type)
    {
        if (type == typeof(int))
            return Variant.Type.Int;
        if (type == typeof(long))
            return Variant.Type.Int;
        if (type == typeof(float))
            return Variant.Type.Float;
        if (type == typeof(double))
            return Variant.Type.Float;
        if (type == typeof(bool))
            return Variant.Type.Bool;
        if (type == typeof(string))
            return Variant.Type.String;
        if (type == typeof(void))
            return Variant.Type.Nil;
        if (type == typeof(byte))
            return Variant.Type.Int;
        if (type == typeof(short))
            return Variant.Type.Int;
        if (type == typeof(char))
            return Variant.Type.Int;
        if (type == typeof(decimal))
            return Variant.Type.Float;
        return Variant.Type.Nil;
    }
}
