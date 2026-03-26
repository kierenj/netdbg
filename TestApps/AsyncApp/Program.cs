namespace AsyncApp;
class Program
{
    static async Task Main()
    {
        Console.WriteLine("Starting async work");
        var result = await DoWorkAsync("hello");
        Console.WriteLine($"Result: {result}");
    }

    static async Task<string> DoWorkAsync(string input)
    {
        await Task.Delay(100);
        var processed = input.ToUpper();
        return $"Processed: {processed}";
    }
}
