using GenerateData.Models;

namespace GenerateData.Generators
{
    public class CounterpartyRoleGenerator : IEntityGenerator<CounterpartyRole>
    {
        public List<CounterpartyRole> Generate(GenerationContext context, int count = 100)
        {
            var predefinedRoles = new List<CounterpartyRole>
            {
                new CounterpartyRole { Name = "supplier" },
                new CounterpartyRole { Name = "customer" },
            };

            context.AvailableRoles.AddRange(predefinedRoles.Select(r => r.Name));

            return predefinedRoles;
        }
    }
}
