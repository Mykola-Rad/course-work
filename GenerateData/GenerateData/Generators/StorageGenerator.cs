using Bogus;
using GenerateData.Models;
using GenerateData.Utills;

namespace GenerateData.Generators
{
    public class StorageGenerator : IEntityGenerator<Storage>
    {
        private static int _storageCounter = 1;
        private const int _maxStreetLength = 100;
        private const int _maxCityLength = 50;
        private const int _maxRegionLength = 30;
        private const int _maxPostalCodeLength = 8;
        private const int _maxBuildingNumberLength = 3;
        public List<Storage> Generate(GenerationContext context, int count = 100)
        {
            var storageFaker = new Faker<Storage>()
                .RuleFor(s => s.Name, f => $"Storage #{_storageCounter++}")
                .RuleFor(s => s.StreetName, f => DataGenerationUtils.GenerateValue(
                    faker => faker.Address.StreetName(), _maxStreetLength, f))
                .RuleFor(s => s.HouseNumber, f => 
                DataGenerationUtils.GenerateValue(faker => faker.Address.BuildingNumber(), _maxBuildingNumberLength, f))
                .RuleFor(s => s.City, f => DataGenerationUtils.GenerateValue(
                    faker => faker.Address.City(), _maxCityLength, f))
                .RuleFor(s => s.Region, f => DataGenerationUtils.GenerateValue(
                    faker => faker.Address.State(), _maxRegionLength, f))
                .RuleFor(s => s.PostalCode, f =>
                DataGenerationUtils.GenerateValue(faker => faker.Address.ZipCode(), _maxPostalCodeLength, f));

            var generatedStorages = storageFaker.Generate(count);

            foreach (string storageName in generatedStorages.Select(s => s.Name))
                if (!context.AvailableStorageKeepers.ContainsKey(storageName))
                    context.AvailableStorageKeepers[storageName] = new List<string>();

                return generatedStorages;
        }
    }
}
