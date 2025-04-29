using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace GenerateData
{
    public interface IEntityGenerator<TEntity> where TEntity : class
    {
       List<TEntity> Generate(int count, GenerationContext context);
    }
}
