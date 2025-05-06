using Bogus;
using GenerateData.Data;
using GenerateData.Models;
using GenerateData.Utills;
using Microsoft.EntityFrameworkCore;

namespace GenerateData.Generators
{
    public class CounterpartyGenerator : IEntityGenerator<Counterparty>
    {
        private readonly AppDbContext _context;
        private const int _maxCompanyLength = 100;

        public CounterpartyGenerator(AppDbContext context)
        {
            _context = context;
        }

        public List<Counterparty> Generate(GenerationContext context, int count = 100)
        {
            var counterpartyFaker = new Faker<Counterparty>()
                .RuleFor(c => c.PhoneNumber, f => f.Phone.PhoneNumber("+380#########"))
                .RuleFor(c => c.Name, f => 
                DataGenerationUtils.GenerateValue(faker => faker.Company.CompanyName(), _maxCompanyLength, f))
                .RuleFor(c => c.Email, f => f.Internet.Email());

            var generatedCounterparties = DataGenerationUtils.GenerateWithUniqueName(
                count,
                counterpartyFaker,
                getName: counterparty => counterparty.Name,         
                setName: (counterparty, name) => counterparty.Name = name);

            var random = new Random();
            foreach (var counterparty in generatedCounterparties)
            {
                var roleNamesToAssign = context.AvailableRoles
                    .OrderBy(r => random.Next())
                    .Take(random.Next(1, context.AvailableRoles.Count + 1))
                    .ToList();


                var rolesToAssign = _context.CounterpartyRoles
                    .Where(r => roleNamesToAssign.Contains(r.Name))
                    .ToList();

                counterparty.Roles = rolesToAssign;
            }

            context.AvailableCounterpartyNames.AddRange(generatedCounterparties.Select(c => c.Name));

            return generatedCounterparties;
        }
    }
}
