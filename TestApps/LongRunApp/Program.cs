namespace LongRunApp;
class Program
{
    static void Main()
    {
        int counter = 0;
        while (true)
        {
            counter++;
            Console.WriteLine($"Tick {counter}");
            Thread.Sleep(2000);
        }
    }
}
