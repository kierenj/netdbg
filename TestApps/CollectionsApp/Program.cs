namespace CollectionsApp;
class Program
{
    static void Main()
    {
        var names = new List<string> { "Alice", "Bob", "Charlie" };
        var scores = new Dictionary<string, int>
        {
            ["Alice"] = 95,
            ["Bob"] = 82,
            ["Charlie"] = 91
        };
        var person = new Person("Alice", 30, new Address("123 Main St", "Springfield"));

        Console.WriteLine($"Count: {names.Count}");
    }
}

record Person(string Name, int Age, Address Home);
record Address(string Street, string City);
