using Bogus;
using GenerateData.Models;

namespace GenerateData.Generators
{
    public class StorageProductGenerator : IEntityGenerator<StorageProduct>
    {
        private const decimal minCount = 1.00m;
        private const decimal maxCount = 100.00m;
        public List<StorageProduct> Generate(int count, GenerationContext context)
        {
            if (!context.AvailableStorageNames.Any() || !context.AvailableProductNames.Any())
            {
                throw new InvalidOperationException(
                    "GenerationContext must contain AvailableStorageNames and AvailableProductNames " +
                    "before generating Products. Ensure ProductGenerator and StorageGenerator run first.");
            }

            var uniqueStorageProducts = new HashSet<(string productName, string storageName)>();
            var storageProducts = new List<StorageProduct>();

            var storageProductFaker = new Faker<StorageProduct>()
                .RuleFor(sp => sp.StorageName, f => f.PickRandom(context.AvailableStorageNames))
                .RuleFor(sp => sp.ProductName, f => f.PickRandom(context.AvailableProductNames))
                .RuleFor(sp => sp.Count, f => Math.Round(f.Random.Decimal(minCount, maxCount), 2));

            while (storageProducts.Count < count)
            {
                var entry = storageProductFaker.Generate();

                var combination = (entry.ProductName, entry.StorageName);
                if (uniqueStorageProducts.Add(combination))
                    storageProducts.Add(entry);
            }

            context.AvailableStorageProducts.AddRange(storageProducts.Select(s => (s.StorageName, s.ProductName)));

            return storageProducts;
        }
    }
}
