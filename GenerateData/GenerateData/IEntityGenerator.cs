using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace GenerateData
{
    public interface IEntityGenerator
    {
       void Generate(int count, GenerationContext context);
    }
}
