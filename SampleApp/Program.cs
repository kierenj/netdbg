namespace SampleApp;

class Program
{
    static void Main(string[] args)
    {
        var items = new List<string> { "apple", "banana", "cherry" };
        var result = FindItem(items, "banana");
        Console.WriteLine($"Found: {result}");

        // Bug: off-by-one causes index out of range
        var prices = new int[] { 10, 20, 30 };
        var total = CalculateTotal(prices);
        Console.WriteLine($"Total: {total}");
    }

    static string FindItem(List<string> items, string target)
    {
        foreach (var item in items)
        {
            if (item == target)
                return item;
        }
        return "not found";
    }

    static int CalculateTotal(int[] prices)
    {
        int sum = 0;
        // Bug: <= should be <, causes IndexOutOfRangeException
        for (int i = 0; i <= prices.Length; i++)
        {
            sum += prices[i];
        }
        return sum;
    }
}
