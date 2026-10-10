using System;
using Godot;

public partial class CSharpAutoload : Node
{
    public void Function() { }

    public void OverloadedFunction() { }

    public void OverloadedFunction(string a) { }

    public void OverloadedFunction(int b) { }

    public void OverloadedFunction(string a, int b) { }
}
