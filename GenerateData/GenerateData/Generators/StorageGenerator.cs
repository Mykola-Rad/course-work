using Bogus;
using GenerateData.Models;
using GenerateData.Utills;

namespace GenerateData.Generators
{
    public class StorageGenerator : IEntityGenerator<Storage>
    {
        private const int maxStreetLength = 100;
        private const int maxCityLength = 50;
        private const int maxRegionLength = 30;
        public List<Storage> Generate(int count, GenerationContext context)
        {
            var storageFaker = new Faker<Storage>()
                .RuleFor(s => s.Name, f => $"Storage #{f.Random.Int(1, count)}")
                .RuleFor(s => s.StreetName, f => DataGenerationUtils.GenerateValue(
                    faker => faker.Address.StreetName(), maxStreetLength, f))
                .RuleFor(s => s.HouseNumber, f => f.Address.BuildingNumber())
                .RuleFor(s => s.City, f => DataGenerationUtils.GenerateValue(
                    faker => faker.Address.City(), maxCityLength, f))
                .RuleFor(s => s.Region, f => DataGenerationUtils.GenerateValue(
                    faker => faker.Address.State(), maxRegionLength, f))
                .RuleFor(s => s.PostalCode, f => f.Address.ZipCode());

            var generatedStorages = storageFaker.Generate(count);

            foreach (string storageName in generatedStorages.Select(s => s.Name))
                if (!context.AvailableStorageKeepers.ContainsKey(storageName))
                    context.AvailableStorageKeepers[storageName] = new List<string>();

                return generatedStorages;
        }
    }
}
