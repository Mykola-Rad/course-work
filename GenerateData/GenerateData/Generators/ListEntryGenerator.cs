using Bogus;
using GenerateData.Models;

namespace GenerateData.Generators
{
    public class ListEntryGenerator : IEntityGenerator<ListEntry>
    {
        private const int minCount = 1;
        private const int maxCount = 100;
        private const decimal minPrice = 10;
        private const decimal maxPrice = 1000;
        public List<ListEntry> Generate(int count, GenerationContext context)
        {
            var uniqueEntries = new HashSet<(string productName, int invoice_id)>();
            var listEntries = new List<ListEntry>();

            var faker = new Faker<ListEntry>()
                .RuleFor(le => le.InvoiceId, f => f.PickRandom(context.AvailableInvoiceIds))
                .RuleFor(le => le.ProductName, f => f.PickRandom(context.AvailableProductNames))
                .RuleFor(le => le.Count, f => Math.Round(f.Random.Decimal(minCount, maxCount), 2))
                .RuleFor(le => le.Price, f => Math.Round(f.Random.Decimal(minPrice, maxPrice), 2));

            while (listEntries.Count < count)
            {
                var entry = faker.Generate();

                var combination = (entry.ProductName, entry.InvoiceId);
                if (uniqueEntries.Add(combination))
                    listEntries.Add(entry);
            }

            return listEntries;
        }
    }
}
