using Bogus;
using GenerateData.Models;
using GenerateData.Utills;

namespace GenerateData.Generators
{
    public class CounterpartyGenerator : IEntityGenerator<Counterparty>
    {
        private const int maxCompanyLength = 100;
        public List<Counterparty> Generate(int count, GenerationContext context)
        {
            var counterpartyFaker = new Faker<Counterparty>()
                .RuleFor(c => c.PhoneNumber, f => f.Phone.PhoneNumber("+380#########"))
                .RuleFor(c => c.Name, f => 
                DataGenerationUtils.GenerateValue(faker => faker.Company.CompanyName(), maxCompanyLength, f))
                .RuleFor(c => c.Email, f => f.Internet.Email());

            var generatedCounterparties = DataGenerationUtils.GenerateWithUniqueName(
                count,
                counterpartyFaker,
                getName: counterparty => counterparty.Name,         
                setName: (counterparty, name) => counterparty.Name = name); 

            context.AvailableCounterpartyNames.AddRange(generatedCounterparties.Select(c => c.Name));

            return generatedCounterparties;
        }
    }
}
