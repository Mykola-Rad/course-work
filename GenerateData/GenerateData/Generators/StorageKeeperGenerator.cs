using Bogus;
using GenerateData.Models;
using GenerateData.Utills;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace GenerateData.Generators
{
    public class StorageKeeperGenerator : IEntityGenerator<StorageKeeper>
    {
        private const int _maxFirstNameLength = 50;
        private const int _maxLastNameLength = 50;
        public List<StorageKeeper> Generate(GenerationContext context, int count = 100)
        {
            if (!context.AvailableStorageKeepers.Keys.Any())
                throw new InvalidOperationException(
                    "Storages must be populated before generating StorageKeepers.");

            var keeperFaker = new Faker<StorageKeeper>()
                .RuleFor(k => k.PhoneNumber, f => f.Phone.PhoneNumber("+380#########"))
                .RuleFor(k => k.FirstName, f => 
                    DataGenerationUtils.GenerateValue(faker => faker.Name.FirstName(), _maxFirstNameLength, f))
                .RuleFor(k => k.LastName, f => 
                    DataGenerationUtils.GenerateValue(faker => faker.Name.LastName(), _maxLastNameLength, f))
                .RuleFor(k => k.Email, f => f.Internet.Email())
                .RuleFor(k => k.StorageName, f => f.PickRandom(context.AvailableStorageKeepers.Keys.ToList()));

            var generatedKeepers = new List<StorageKeeper>();

            List<string> keeperUsernames = context.AvailableKeeperUsernames;

            while (keeperUsernames.Count > 0 && generatedKeepers.Count < count)
            {
                var keeper = keeperFaker.Generate();
                keeper.Username = keeperUsernames[0];
                keeperUsernames.RemoveAt(0);
                generatedKeepers.Add(keeper);
            }

            if (generatedKeepers.Count < count)
                generatedKeepers.AddRange(keeperFaker.Generate(count - generatedKeepers.Count));

            foreach (var storageKeeper in generatedKeepers)
                context.AvailableStorageKeepers[storageKeeper.StorageName].Add(storageKeeper.PhoneNumber);

            return generatedKeepers;
        }
    }
}
