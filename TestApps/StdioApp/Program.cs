namespace StdioApp;
class Program
{
    static void Main()
    {
        Console.WriteLine("stdout: hello from stdout");
        Console.Error.WriteLine("stderr: hello from stderr");
        Console.Write("Enter your name: ");
        var name = Console.ReadLine();
        Console.WriteLine($"stdout: Hello, {name}!");
        Console.Error.WriteLine("stderr: done");
    }
}
