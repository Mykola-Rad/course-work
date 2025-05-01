using Bogus;
using GenerateData.Models;
using GenerateData.Utills;

namespace GenerateData.Generators
{
    public class ProductGenerator : IEntityGenerator<Product>
    {
        private const int _maxProductNameLength = 100;
        private const decimal _minProductPrice = 1.00m;
        private const decimal _maxProductPrice = 5000.00m;
        public List<Product> Generate(GenerationContext context, int count = 100)
        {
            if (!context.AvailableUnitCodes.Any())
                throw new InvalidOperationException(
                    "GenerationContext must contain AvailableUnitCodes " +
                    "before generating Products. Ensure ProductUnitGenerator runs first.");

            var productFaker = new Faker<Product>()
                .RuleFor(p => p.ProductName, f => DataGenerationUtils.GenerateValue(
                    faker => faker.Commerce.ProductName(), _maxProductNameLength, f))
                .RuleFor(p => p.UnitCode, f => f.PickRandom(context.AvailableUnitCodes))
                .RuleFor(p => p.LastPrice, f => Math.Round(f.Random.Decimal(_minProductPrice, _maxProductPrice), 2));

            var generatedProducts = DataGenerationUtils.GenerateWithUniqueName(
                count,
                productFaker,
                getName: product => product.ProductName,
                setName: (product, name) => product.ProductName = name);

            context.AvailableProductNames.AddRange(generatedProducts.Select(p => p.ProductName));

            return generatedProducts;
        }
    }
}
